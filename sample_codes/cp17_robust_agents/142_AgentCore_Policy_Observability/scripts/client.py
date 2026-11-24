"""Call add twice and record public correlation information, never tokens."""
import argparse
import asyncio
from datetime import datetime, timezone
import json
from pathlib import Path
import secrets
import time

import httpx2 as httpx

from common import ROOT, settings
from login import login
from transport import GatewayClient, McpError


def validate_calls(cases):
    if cases[0].get('result') != {'a': 1, 'b': 2, 'sum': 3}:
        raise RuntimeError('The allowed call did not return 3; see saved result')
    if cases[1]['outcome'] != 'mcp_error' or cases[1].get('error_code') != -32002:
        raise RuntimeError('Expected MCP policy denial (-32002); see saved result')


async def exercise(token, output=ROOT / 'results/latest-calls.json'):
    config = settings()
    started = time.time()
    cases = []
    try:
        async with httpx.AsyncClient(headers={'Authorization': 'Bearer ' + token},
                                     timeout=120) as http:
            mcp = GatewayClient(http, config['mcp_url'])
            await mcp.initialize()
            for label, a, b in [('allow', 1, 2), ('deny', 101, 2)]:
                epoch = int(time.time())
                trace = f'{epoch:08x}' + secrets.token_hex(12)
                parent = secrets.token_hex(8)
                mcp.headers.update({'X-Amzn-Trace-Id': f'Root=1-{trace[:8]}-{trace[8:]};Parent={parent};Sampled=1',
                                    'traceparent': f'00-{trace}-{parent}-01'})
                case = {'case': label, 'a': a, 'b': b, 'trace_id': trace,
                        'timestamp': datetime.now(timezone.utc).isoformat()}
                try:
                    result = await mcp.call_tool(config['tool_prefix'] + 'add', {'a': a, 'b': b})
                except McpError as error:
                    case.update(outcome='mcp_error', error_code=error.error.code,
                                error_message=error.error.message)
                else:
                    if result.get('isError'):
                        raise RuntimeError('Backend tool failed; not proof of a Policy rejection')
                    value = result.get('structuredContent') or json.loads(result['content'][0]['text'])
                    case.update(outcome='success', result=value)
                case.update(mcp.last_response)
                cases.append(case)
                print(json.dumps(case, ensure_ascii=False), flush=True)
    finally:
        result = {'started_at_epoch': started, 'finished_at_epoch': time.time(), 'calls': cases}
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    validate_calls(cases)
    print('Calls completed. Confirm ALLOW/DENY and determining policies in AWS spans.', flush=True)
    return result


def report_failure(error):
    print('Failure type: ' + type(error).__name__, flush=True)
    if type(error) is RuntimeError:
        print(str(error), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-browser', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT / 'results/latest-calls.json')
    args = parser.parse_args()
    try:
        print('Cognitoに reader でログインしてください。パスワードはユーザー作成時に設定したものです。', flush=True)
        token = login(settings(), no_browser=args.no_browser)
        asyncio.run(exercise(token, args.output))
    except Exception as error:
        report_failure(error)
        raise SystemExit(1) from None
