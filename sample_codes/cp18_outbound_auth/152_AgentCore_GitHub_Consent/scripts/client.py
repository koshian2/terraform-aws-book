"""Cognito authenticates the MCP caller; connect GitHub on the managed portal."""
import argparse
import asyncio
import os
from common import settings
import httpx
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client


async def run(args):
    config = settings()
    if args.action == 'portal':
        print(config['portal_url'])
        return 0
    token = os.environ.get('AGENTCORE_ACCESS_TOKEN', '').strip()
    if not token:
        raise SystemExit('Run login.py and set AGENTCORE_ACCESS_TOKEN first')
    async with httpx.AsyncClient(headers={'Authorization': 'Bearer ' + token},
            timeout=120) as http:
        async with streamable_http_client(config['mcp_url'], http_client=http,
                terminate_on_close=False) as (read, write, _):
            async with ClientSession(read, write) as session:
                initialized = await session.initialize()
                print('Negotiated MCP protocol: ' + str(initialized.protocolVersion))
                if args.action == 'list':
                    result = await session.list_tools()
                else:
                    if args.issue_number < 1:
                        raise ValueError('Issue number must be positive')
                    result = await session.call_tool(config['tool_prefix'] + 'get_issue',
                                                      {'issue_number': args.issue_number})
                print(result.model_dump_json(indent=2))
                if getattr(result, 'isError', False):
                    print('MCP tool returned an error. See content above for the cause.')
                    print('Only if the error requires consent, open: ' + config['portal_url'])
                    return 1
    return 0


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('action', choices=['portal', 'list', 'get'])
    p.add_argument('issue_number', nargs='?', type=int, default=1)
    raise SystemExit(asyncio.run(run(p.parse_args())))
