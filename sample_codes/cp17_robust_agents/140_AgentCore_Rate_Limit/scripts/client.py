"""Single calls or a bounded throttle/recovery experiment; no hidden retries."""
import argparse
import asyncio
import json
import math
from datetime import datetime, timezone
from types import SimpleNamespace
import time

import httpx2 as httpx

from common import ROOT, settings
from login import login


class McpError(Exception):
    def __init__(self, error):
        self.error = SimpleNamespace(code=error.get('code'), data=error.get('data'))
        super().__init__('Gateway returned a JSON-RPC error')

def throttle_details(error, expected_limit='add-per-minute'):
    """Accept only this Gateway limit, never authentication/transport/tool errors."""
    data = error.data
    if error.code != -32003 or not isinstance(data, dict):
        raise RuntimeError('Unexpected MCP error; not the configured rate limit')
    key = data.get('limitKey')
    if not isinstance(key, str) or key.split('/')[0] != expected_limit or data.get('metric') != 'requests':
        raise RuntimeError('Throttled by a different limit or metric')
    delay = data.get('retryAfter')
    if isinstance(delay, bool) or not isinstance(delay, (int, float)) or not math.isfinite(delay) or delay < 0:
        raise RuntimeError('Missing or invalid retryAfter')
    return {'code': error.code, 'limitKey': key, 'metric': 'requests', 'retryAfter': delay}


class GatewayClient:
    """Small JSON-RPC client for this stateless Gateway demo; zero implicit retries.

    Decode MCP errors even when HTTP status is 429. The SDK transport can close
    the session on non-2xx responses before exposing the JSON-RPC error body.
    """
    def __init__(self, http, url):
        self.http, self.url = http, url
        self.counter = 0
        self.records = []
        self.headers = {'Accept': 'application/json, text/event-stream'}

    async def rpc(self, method, params, notification=False):
        self.counter += 1
        body = {'jsonrpc': '2.0', 'method': method, 'params': params}
        if not notification:
            body['id'] = self.counter
        record = {'sent_at': datetime.now(timezone.utc).isoformat(), 'method': method, 'params': params}
        self.records.append(record)
        async with self.http.stream('POST', self.url, headers=self.headers, json=body) as response:
            record.update(http_status=response.status_code, response_at=datetime.now(timezone.utc).isoformat(), request_id=response.headers.get('x-amzn-requestid'))
            if response.headers.get('mcp-session-id'):
                self.headers['Mcp-Session-Id'] = response.headers['mcp-session-id']
            if notification:
                response.raise_for_status()
                return None
            if response.status_code not in (200, 429):
                response.raise_for_status()
            if 'text/event-stream' in response.headers.get('content-type', ''):
                parts = []
                message = None
                async for line in response.aiter_lines():
                    if line.startswith('data:'):
                        parts.append(line[5:].lstrip())
                    elif not line and parts:
                        candidate = json.loads('\n'.join(parts))
                        parts = []
                        if candidate.get('id') == body['id']:
                            message = candidate
                            break
                if message is None:
                    raise RuntimeError('SSE stream ended without the expected response')
            else:
                await response.aread()
                message = response.json()
            record['response'] = message
            if not isinstance(message, dict) or message.get('jsonrpc') != '2.0' or message.get('id') != body['id']:
                raise RuntimeError('Invalid JSON-RPC response')
            if 'error' in message:
                error = message['error']
                if not isinstance(error, dict):
                    response.raise_for_status()
                    raise RuntimeError('Unexpected Gateway error format')
                print('Gateway HTTP status:', response.status_code, flush=True)
                raise McpError(error)
            response.raise_for_status()
            if 'result' not in message:
                raise RuntimeError('Invalid JSON-RPC response')
            return message['result']

    async def initialize(self):
        result = await self.rpc('initialize', {'protocolVersion': '2025-11-25',
            'capabilities': {}, 'clientInfo': {'name': 'rate-limit-demo', 'version': '1.0'}})
        self.headers['MCP-Protocol-Version'] = result['protocolVersion']
        await self.rpc('notifications/initialized', {}, notification=True)

    async def list_tools(self):
        return await self.rpc('tools/list', {})

    async def call_tool(self, name, arguments):
        return await self.rpc('tools/call', {'name': name, 'arguments': arguments})


async def call_add(mcp, tool_name, a, b):
    start = time.monotonic()
    try:
        result = await mcp.call_tool(tool_name, {'a': a, 'b': b})
    except McpError as error:
        detail = error.error.data if isinstance(error.error.data, dict) else {}
        print(json.dumps({'gateway_error_code': error.error.code,
                          **{key: detail.get(key) for key in ('limitKey', 'metric', 'retryAfter')}}), flush=True)
        data = {'status': 'throttled', **throttle_details(error.error)}
    else:
        if result.get('isError'):
            raise RuntimeError('Backend tool failed; not a Gateway rate-limit result')
        value = result.get('structuredContent') or json.loads(result['content'][0]['text'])
        if value != {'a': a, 'b': b, 'sum': a + b}:
            raise RuntimeError('Incorrect calculation result')
        data = {'status': 'success', **value}
    data['elapsed_seconds'] = round(time.monotonic() - start, 3)
    print(json.dumps(data, ensure_ascii=False), flush=True)
    return data


async def wait_for_recovery(mcp, tool_name, throttle, budget=180):
    deadline = time.monotonic() + budget
    for _ in range(10):
        delay = max(1, math.ceil(throttle['retryAfter'])) + 1
        if time.monotonic() + delay >= deadline:
            raise RuntimeError('Recovery wait exceeds the bounded test deadline')
        print(f'Waiting {delay}s based on retryAfter; no other calls during this wait', flush=True)
        await asyncio.sleep(delay)
        result = await call_add(mcp, tool_name, 100, 1)
        if result['status'] == 'success':
            return
        throttle = result
    raise RuntimeError('Recovery did not occur within the retry budget')


async def verify_rate_limit(mcp, config):
    tool = config['tool_prefix'] + 'add'
    tools = (await mcp.list_tools())['tools']
    if {t['name'] for t in tools} != {tool}:
        raise RuntimeError('Unexpected tools')
    successes = 0
    throttle = None
    started = time.monotonic()
    # No automatic retry in this phase. Stop immediately at the first throttle.
    for i in range(1, 61):
        if time.monotonic() - started > 180:
            break
        result = await call_add(mcp, tool, i, i)
        if result['status'] == 'throttled':
            throttle = result
            break
        successes += 1
    if throttle is None:
        raise RuntimeError('No rate limit observed within 60 calls / 180s; inspect configuration and traffic')
    # A previous Codex run can consume the shared budget before this test starts.
    print(f'PASS: configured Gateway limit observed after {successes} successful calls', flush=True)
    tools = (await mcp.list_tools())['tools']
    if {t['name'] for t in tools} != {tool}:
        raise RuntimeError('Tool discovery changed while throttled')
    print('PASS: tools/list still works while add is throttled', flush=True)
    await wait_for_recovery(mcp, tool, throttle)
    print('PASS: add recovered after waiting; no infrastructure settings changed', flush=True)


async def run(args):
    config = settings()
    print('Cognitoに reader でログインしてください。パスワードはユーザー作成時に設定したものです。', flush=True)
    token = login(config, no_browser=args.no_browser)
    if args.action == 'verify':
        print('レート制限設定の反映を35秒待ちます。', flush=True)
        await asyncio.sleep(35)
    folder = ROOT / 'results'
    folder.mkdir(exist_ok=True)
    path = folder / ('run-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '.json')
    async with httpx.AsyncClient(headers={'Authorization': 'Bearer ' + token}, timeout=30) as http:
        mcp = GatewayClient(http, config['mcp_url'])
        try:
            await mcp.initialize()
            if args.action == 'list':
                print(json.dumps(await mcp.list_tools(), ensure_ascii=False, indent=2))
            elif args.action == 'verify':
                await verify_rate_limit(mcp, config)
            else:
                result = await call_add(mcp, config['tool_prefix'] + 'add', args.a, args.b)
                if result['status'] == 'throttled':
                    return 2
        finally:
            path.write_text(json.dumps(mcp.records, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
            print(f'記録: {path}', flush=True)
    return 0


def report_failure(error):
    """Print our fixed diagnostic messages, never HTTP URLs or auth responses."""
    if isinstance(error, BaseExceptionGroup):
        for child in error.exceptions:
            report_failure(child)
    elif type(error) is RuntimeError:
        print(str(error), flush=True)
    else:
        print('Failure type: ' + type(error).__name__, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['list', 'add', 'verify'])
    parser.add_argument('--a', type=int, default=1)
    parser.add_argument('--b', type=int, default=1)
    parser.add_argument('--no-browser', action='store_true')
    args = parser.parse_args()
    try:
        status = asyncio.run(run(args))
    except Exception as error:
        report_failure(error)
        raise SystemExit('Client failed; see last completed step. Credentials and response bodies omitted.') from None
    raise SystemExit(status)
