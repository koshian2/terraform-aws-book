"""4人でテナント共有・分離とProの回復を観察する。未判定も記録する。"""
import argparse
import asyncio
from contextlib import AsyncExitStack
from datetime import datetime, timezone
import json
import subprocess
import time

import boto3
import httpx2

from common import ROOT, settings
from client import GatewayClient, call_add, wait_for_recovery, report_failure
from identity import login_user


class Inconclusive(RuntimeError):
    pass


def check_configuration(config):
    result = subprocess.check_output(
        ['terraform', f'-chdir={ROOT / "terraform"}', 'output', '-json', 'rate_limit_config'], encoding='utf-8')
    expected = json.loads(result)
    aws = boto3.Session(profile_name=config['aws_profile'], region_name=config['aws_region'])
    actual = aws.client('bedrock-agentcore-control').get_gateway_rate_limit(
        gatewayIdentifier=config['gateway_id'], rateLimitId=expected['id'])
    entries = [{
        'dimensions': {'toolName': expected['tool_name'], '$.context.jwt.tier': tier, '$.context.jwt.tenant_id': '*'},
        'requests': [{'rate': rate, 'period': 'minute'}],
    } for tier, rate in sorted(expected['tier_rates'].items())]
    if (actual['status'] != 'ACTIVE' or actual['dimensionKeys'] != expected['dimension_keys']
            or sorted(actual['entries'], key=lambda e: e['dimensions']['$.context.jwt.tier']) != entries):
        raise RuntimeError('AWS上のレート制限が期待するACTIVEな設定と一致しません。')
    return expected


async def exhaust(invoke, user):
    started = time.monotonic()
    successes = 0
    try:
        async with asyncio.timeout(120):
            for first in range(1, 61, 5):
                # TaskGroupで失敗・期限切れ時に残りの呼び出しも終了させる。
                async with asyncio.TaskGroup() as group:
                    tasks = [group.create_task(invoke(user, i)) for i in range(first, first + 5)]
                results = [task.result() for task in tasks]
                successes += sum(r['status'] == 'success' for r in results)
                if all(r['status'] == 'throttled' for r in results):
                    print(f'{user}: {successes}成功 / {first + 4}回、{time.monotonic() - started:.1f}秒。5件すべて制限されました。', flush=True)
                    return results[-1]
    except TimeoutError:
        raise Inconclusive('負荷観測が120秒を超えました。') from None
    raise Inconclusive('60回以内に5件すべてが制限される状態を観測できませんでした。')


async def compare(config, tokens, identities, report):
    tool = config['tool_prefix'] + 'add'
    clients = {}
    try:
        async with AsyncExitStack() as stack:
            for user, token in tokens.items():
                http = await stack.enter_async_context(httpx2.AsyncClient(
                    headers={'Authorization': 'Bearer ' + token}, timeout=30))
                clients[user] = GatewayClient(http, config['mcp_url'])
                await clients[user].initialize()
                if {t['name'] for t in (await clients[user].list_tools())['tools']} != {tool}:
                    raise RuntimeError('Unexpected tool list')

            async def invoke(user, number):
                stamp = datetime.now(timezone.utc).isoformat()
                result = await call_add(clients[user], tool, number, number)
                record = {'sent_at': stamp, **identities[user], **result}
                report['observations'].append(record)
                print(json.dumps(record, ensure_ascii=False), flush=True)
                return result

            async def probe(pairs):
                async with asyncio.TaskGroup() as group:
                    tasks = [group.create_task(invoke(user, n)) for user, n in pairs]
                return [task.result() for task in tasks]

            await exhaust(invoke, 'alice')
            a1, a2, b = await probe([('alice', 101), ('alice2', 102), ('bob', 103)])
            shared = a1['status'] == a2['status'] == 'throttled' and b['status'] == 'success'
            report['checks']['tenant_a_shared_and_b_independent'] = 'PASS' if shared else 'INCONCLUSIVE'

            await exhaust(invoke, 'bob')
            b, c = await probe([('bob', 104), ('carol', 105)])
            independent = b['status'] == 'throttled' and c['status'] == 'success'
            report['checks']['tenant_b_limited_and_c_available'] = 'PASS' if independent else 'INCONCLUSIVE'

            throttle = await exhaust(invoke, 'carol')
            await wait_for_recovery(clients['carol'], tool, throttle)
            report['checks']['pro_throttle_and_recovery'] = 'PASS'
            if not shared or not independent:
                raise Inconclusive('一部の共有・分離の比較条件を観測できませんでした。記録を確認してください。')
    finally:
        report['requests'] = {user: client.records for user, client in clients.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-browser', action='store_true')
    args = parser.parse_args()
    config = settings()
    tokens, identities = {}, {}
    report = {'status': 'ERROR', 'checks': {}, 'observations': []}
    folder = ROOT / 'results'
    folder.mkdir(exist_ok=True)
    path = folder / ('compare-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '.json')
    try:
        report['configuration'] = check_configuration(config)
        for user in ('alice', 'alice2', 'bob', 'carol'):
            tokens[user], identities[user] = login_user(config, user, no_browser=args.no_browser)
        if len({i['sub'] for i in identities.values()}) != 4:
            raise RuntimeError('4人の異なるユーザーでログインしてください。')
        report['identities'] = identities
        print('全員のログインが完了しました。設定反映を35秒待って比較を開始します。', flush=True)
        time.sleep(35)
        asyncio.run(compare(config, tokens, identities, report))
        report['status'] = 'PASS'
    except Inconclusive as exc:
        report['status'] = 'INCONCLUSIVE'
        report['reason'] = str(exc)
        print(f'INCONCLUSIVE: {exc}', flush=True)
    except Exception as exc:
        report['error_type'] = type(exc).__name__
        report_failure(exc)
    finally:
        path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(f'結果: {report["status"]} / 記録: {path}', flush=True)
    return 0 if report['status'] == 'PASS' else 2 if report['status'] == 'INCONCLUSIVE' else 1


if __name__ == '__main__':
    raise SystemExit(main())
