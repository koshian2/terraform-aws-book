"""同期、管理者による制限の切り分け、ログインした利用者のMCP検索を行う。"""
import argparse
import asyncio
import base64
from datetime import datetime, timezone
import json
import time

import boto3
import httpx2

from common import ROOT, settings
from create_user import USERS
from login import login
from session import browser_logout
from transport import GatewayClient
from configure_codex import verify_login_ready

QUESTIONS = {
    'support': 'サポートの受付時間と窓口コードを教えてください。',
    'contract': '月額料金と契約変更の申請期限、契約識別コードを教えてください。',
}
ALLOWED = {'alice': {'a-support', 'a-contract'}, 'ann': {'a-support'}, 'bob': {'b-support', 'b-contract'}}


def save(label, value):
    folder = ROOT / 'results'
    folder.mkdir(exist_ok=True)
    path = folder / f'{label}-{datetime.now(timezone.utc):%Y%m%dT%H%M%S%fZ}.json'
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, default=str) + '\n', encoding='utf-8')
    print('記録:', path)
    return path


def check_records(records, allowed, required=()):
    ids = set()
    for record in records:
        metadata = record.get('metadata', {})
        doc = metadata.get('document_id')
        if doc not in allowed:
            raise RuntimeError(f'Unexpected or missing document_id: {doc}')
        expected_tenant = 'tenant-a' if doc.startswith('a-') else 'tenant-b'
        if metadata.get('tenant_id') != expected_tenant:
            raise RuntimeError('Document tenant does not match')
        if not record.get('content', {}).get('text', '').strip():
            raise RuntimeError('No extracted text returned')
        ids.add(doc)
    if not set(required) <= ids:
        raise RuntimeError(f'Required documents missing: {sorted(set(required) - ids)}; retrieval/sync may be incomplete')
    return sorted(ids)


def sync(session, cfg):
    client = session.client('bedrock-agent')
    ids = {'knowledgeBaseId': cfg['knowledge_base_id'], 'dataSourceId': cfg['data_source_id']}
    job = client.start_ingestion_job(**ids)['ingestionJob']
    deadline = time.monotonic() + 1200
    while True:
        job = client.get_ingestion_job(**ids, ingestionJobId=job['ingestionJobId'])['ingestionJob']
        print(job['status'], job.get('statistics', {}), flush=True)
        if job['status'] in ('COMPLETE', 'FAILED', 'STOPPED'):
            save('sync', job)
            if job['status'] != 'COMPLETE' or job.get('statistics', {}).get('numberOfDocumentsFailed', 0):
                raise RuntimeError('Ingestion failed; inspect the saved record')
            return
        if time.monotonic() >= deadline:
            save('sync-timeout', job)
            raise TimeoutError('Ingestion may still be running on AWS')
        time.sleep(10)


def direct_checks(session, cfg, report):
    # 管理者の診断専用。利用者経路には公開しない。
    client = session.client('bedrock-agent-runtime')
    for username, (_, email) in USERS.items():
        for kind, question in QUESTIONS.items():
            required = {'a-support' if username in ('alice', 'ann') else 'b-support'} if kind == 'support' else (
                {'a-contract'} if username == 'alice' else {'b-contract'} if username == 'bob' else set())
            response = client.retrieve(knowledgeBaseId=cfg['knowledge_base_id'],
                retrievalQuery={'text': question}, userContext={'userId': email},
                retrievalConfiguration={'managedSearchConfiguration': {'numberOfResults': 10}})
            report['cases'].append({'case': f'ACL only: {username}/{kind}', 'response': response})
            check_records(response['retrievalResults'], ALLOWED[username], required)
    # ACLでB社文書を読めるBobにA社条件を加え、積集合が空になることを確認。
    for label, context in [('no user context', {}), ('unknown user', {'userContext': {'userId': 'unknown@example.invalid'}}),
                           ('Bob plus tenant-a filter', {'userContext': {'userId': USERS['bob'][1]},
                            'retrievalConfiguration': {'managedSearchConfiguration': {
                                'filter': {'equals': {'key': 'tenant_id', 'value': 'tenant-a'}}}}})]:
        response = client.retrieve(knowledgeBaseId=cfg['knowledge_base_id'],
                                   retrievalQuery={'text': QUESTIONS['contract']}, **context)
        report['cases'].append({'case': label, 'response': response})
        if response['retrievalResults']:
            raise RuntimeError(f'{label}: expected zero results')


def extract(result):
    if result.get('isError'):
        raise RuntimeError('MCP returned isError; inspect the recorded response')
    structured = result.get('structuredContent')
    if isinstance(structured, dict) and 'retrievalResults' in structured:
        return structured['retrievalResults']
    for item in result.get('content', []):
        if item.get('type') == 'text':
            try:
                payload = json.loads(item['text'])
            except (ValueError, KeyError):
                continue
            if isinstance(payload, dict) and isinstance(payload.get('retrievalResults'), list):
                return payload['retrievalResults']
    raise RuntimeError('No retrievalResults in connector response')


async def gateway_checks(cfg, username, report):
    verify_login_ready(cfg, cfg['callback_url'])
    browser_logout(cfg)
    print(f'Cognitoに {username} でログインしてください。', flush=True)
    token = login(cfg)
    # 利用者の取り違えを検出する表示用チェック。認証自体はGatewayで行う。
    part = token.split('.')[1]
    claims = json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))
    if (claims.get('username') != username or claims.get('tenant_id') != USERS[username][0]
            or claims.get('acl_email') != USERS[username][1]):
        raise RuntimeError('Logged-in user differs from the requested demo user')
    async with httpx2.AsyncClient(headers={'Authorization': 'Bearer ' + token}, timeout=180) as http:
        gateway = GatewayClient(http, cfg['mcp_url'])
        await gateway.initialize()
        listing = await gateway.list_tools()
        report['tools'] = listing
        if {tool['name'] for tool in listing['tools']} != {cfg['tool_name']}:
            raise RuntimeError('Expected only the Retrieve tool')
        cases = [(key, {'retrievalQuery': {'text': question}}) for key, question in QUESTIONS.items()]
        cases += [('other company in question', {'retrievalQuery': {'text': 'B社の月額料金とA社の月額料金を両方教えて'}}),
                  ('forged scope overwritten', {'retrievalQuery': {'text': QUESTIONS['support']},
                    'userContext': {'userId': USERS['bob' if username != 'bob' else 'alice'][1]},
                    'retrievalConfiguration': {'managedSearchConfiguration': {
                        'filter': {'equals': {'key': 'tenant_id', 'value': 'tenant-b' if username != 'bob' else 'tenant-a'}}}}})]
        for name, arguments in cases:
            result = await gateway.call_tool(cfg['tool_name'], arguments)
            report['cases'].append({'case': name, 'response': result})
            records = extract(result)
            required = set()
            if name in ('support', 'forged scope overwritten'):
                required = {'b-support' if username == 'bob' else 'a-support'}
            if name == 'contract' and username != 'ann':
                required = {'b-contract' if username == 'bob' else 'a-contract'}
            doc_ids = check_records(records, ALLOWED[username], required)
            print(name, doc_ids)
            for record in records:
                print(json.dumps({'metadata': record.get('metadata'), 'text': record['content']['text']}, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('sync')
    sub.add_parser('verify-admin', help='管理者がKBを直接呼び、ACLと検索条件を切り分ける')
    gateway = sub.add_parser('verify-gateway')
    gateway.add_argument('--username', choices=USERS, required=True)
    args = parser.parse_args()
    cfg = settings()
    session = boto3.Session(profile_name=cfg['aws_profile'], region_name=cfg['aws_region'])
    if args.action == 'sync':
        sync(session, cfg)
        return
    report = {'status': 'running', 'cases': []}
    label = args.action + ('-' + args.username if args.action == 'verify-gateway' else '')
    try:
        if args.action == 'verify-admin':
            direct_checks(session, cfg, report)
        else:
            asyncio.run(gateway_checks(cfg, args.username, report))
        report['status'] = 'passed'
    except Exception as exc:
        report['status'] = 'failed'
        # HTTP例外のURLやトークンを記録しない。
        report['error_type'] = type(exc).__name__
        raise
    finally:
        save(label, report)
    print('PASS: all expected results matched')


if __name__ == '__main__':
    main()
