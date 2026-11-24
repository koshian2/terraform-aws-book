"""一般会員とVIPで、Policy・Interceptor・Runtimeの結果を比較する。"""
import argparse
import asyncio
from datetime import datetime, timezone
import json
import httpx2 as httpx
from common import ROOT, settings
from login import login
from session import browser_logout
from transport import GatewayClient, McpError


async def run(args):
    cfg = settings()
    browser_logout(cfg)
    print(f'Cognitoに {args.member} でログインしてください。', flush=True)
    token = login(cfg)
    records = []
    path = ROOT / 'results' / (args.member + '-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '.json')
    cases = [('A', 'policy_denied')] if args.member == 'regular' else [
        ('A', 'demo_accepted'), ('B', 'not_presale_product'), ('C', 'presale_not_started')]
    try:
        async with httpx.AsyncClient(headers={'Authorization': 'Bearer ' + token}, timeout=120) as http:
            mcp = GatewayClient(http, cfg['mcp_url'])
            await mcp.initialize()
            # 一般会員は一覧でツールが非表示でも、既知の名前で直接呼んで拒否を確認する。
            for product, expected in cases:
                record = {'member': args.member, 'product_id': product, 'expected': expected,
                          'timestamp': datetime.now(timezone.utc).isoformat()}
                records.append(record)
                try:
                    result = await mcp.call_tool(cfg['tool_prefix'] + 'reserve_product', {'product_id': product})
                except McpError as error:
                    record.update(error_code=error.error.code)
                    if error.error.code == -32002:
                        actual = 'policy_denied'
                    elif error.error.code == -32048 and isinstance(error.error.data, dict) and error.error.data.get('source') == 'request_interceptor':
                        actual = error.error.data.get('reason')
                    else:
                        raise RuntimeError('Unexpected MCP error; not an expected authorization result') from None
                else:
                    if result.get('isError'):
                        raise RuntimeError('Runtime returned a tool error')
                    value = result.get('structuredContent') or json.loads(result['content'][0]['text'])
                    record['result'] = value
                    if value != {'product_id': product, 'status': 'demo_accepted', 'persisted': False}:
                        raise RuntimeError('Unexpected reservation result')
                    actual = 'demo_accepted'
                record.update(mcp.last_response)
                record.update(actual=actual, matched=actual == expected)
                print(json.dumps(record, ensure_ascii=False), flush=True)
                if actual != expected:
                    raise RuntimeError('Result differs from expectation; check the signed-in user and deployment')
    finally:
        path.parent.mkdir(exist_ok=True)
        path.write_text(json.dumps(records, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(f'記録: {path}', flush=True)
    print('PASS: all expected results matched', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--member', choices=['regular', 'vip'], required=True)
    args = parser.parse_args()
    try:
        asyncio.run(run(args))
    except Exception as error:
        print(str(error) if type(error) is RuntimeError else 'Failure type: ' + type(error).__name__)
        raise SystemExit(1) from None
