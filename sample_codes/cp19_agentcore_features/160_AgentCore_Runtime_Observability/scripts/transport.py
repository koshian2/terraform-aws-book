import json
from mcp.shared.exceptions import McpError
from mcp.types import CallToolResult, ErrorData, ListToolsResult


class GatewayClient:
    """Small JSON-RPC client for this stateless Gateway demo; zero implicit retries.

    Policy denial can be a JSON-RPC error inside HTTP 200. Also decode errors
    in non-2xx responses before closing the transport.
    """
    def __init__(self, http, url):
        self.http, self.url = http, url
        self.counter = 0
        self.last_response = {}
        self.headers = {'Accept': 'application/json, text/event-stream'}

    async def rpc(self, method, params, notification=False):
        self.counter += 1
        body = {'jsonrpc': '2.0', 'method': method, 'params': params}
        if not notification:
            body['id'] = self.counter
        async with self.http.stream('POST', self.url, headers=self.headers, json=body) as response:
            self.last_response = {'http_status': response.status_code, 'request_id': response.headers.get('x-amzn-requestid', response.headers.get('x-amzn-request-id'))}
            if response.headers.get('mcp-session-id'):
                self.headers['Mcp-Session-Id'] = response.headers['mcp-session-id']
            if notification:
                response.raise_for_status()
                return None
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
            if 'error' in message:
                error = message['error']
                if not isinstance(error, dict):
                    response.raise_for_status()
                    raise RuntimeError('Unexpected Gateway error format')
                print('Gateway HTTP status:', response.status_code, flush=True)
                raise McpError(ErrorData.model_validate(error))
            response.raise_for_status()
            if message.get('id') != body['id'] or 'result' not in message:
                raise RuntimeError('Invalid JSON-RPC response')
            return message['result']

    async def initialize(self):
        result = await self.rpc('initialize', {'protocolVersion': '2025-11-25',
            'capabilities': {}, 'clientInfo': {'name': 'runtime-observability-demo', 'version': '1.0'}})
        self.headers['MCP-Protocol-Version'] = result['protocolVersion']
        await self.rpc('notifications/initialized', {}, notification=True)

    async def list_tools(self):
        return ListToolsResult.model_validate(await self.rpc('tools/list', {}))

    async def call_tool(self, name, arguments):
        return CallToolResult.model_validate(await self.rpc('tools/call', {'name': name, 'arguments': arguments}))
