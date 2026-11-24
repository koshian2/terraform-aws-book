"""Shared Memory ABAC demo. Data operations always use tenant credentials."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

ROOT = Path(__file__).resolve().parents[1]
OPTIONS = Config(connect_timeout=10, read_timeout=30,
                 retries={'mode': 'standard', 'total_max_attempts': 3})
TENANTS = ('tenant-a', 'tenant-b')


def settings():
    result = subprocess.run(['terraform', 'output', '-json', 'client_config'],
                            cwd=ROOT / 'terraform', capture_output=True, text=True,
                            encoding='utf-8', check=True)
    return json.loads(result.stdout)


def assume(sts, config, tenant):
    # No caller-supplied actor/namespace checks here: IAM enforces data scope.
    result = sts.assume_role(RoleArn=config['role_arn'],
        RoleSessionName='memory-' + tenant, DurationSeconds=3600,
        Tags=[{'Key': 'TenantId', 'Value': tenant}])
    c = result['Credentials']
    return boto3.Session(aws_access_key_id=c['AccessKeyId'],
        aws_secret_access_key=c['SecretAccessKey'], aws_session_token=c['SessionToken'],
        region_name=config['aws_region'])


def namespace(actor):
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,100}', actor):
        raise ValueError('actor must contain 1-100 letters, digits, underscores or hyphens')
    return '/facts/' + actor + '/'


def save(client, config, actor, session, text):
    return client.create_event(memoryId=config['memory_id'], actorId=actor,
        sessionId=session, eventTimestamp=datetime.now(timezone.utc),
        clientToken=str(uuid.uuid4()),
        payload=[{'conversational': {'role': 'USER', 'content': {'text': text}}}])['event']['eventId']


def history(client, config, actor, session):
    return [event for page in client.get_paginator('list_events').paginate(
        memoryId=config['memory_id'], actorId=actor, sessionId=session,
        includePayloads=True) for event in page['events']]


def records(client, config, actor):
    return [record for page in client.get_paginator('list_memory_records').paginate(
        memoryId=config['memory_id'], namespace=namespace(actor),
        memoryStrategyId=config['strategy_id']) for record in page['memoryRecordSummaries']]


def retrieve(client, config, actor, query):
    return client.retrieve_memory_records(memoryId=config['memory_id'],
        namespace=namespace(actor),
        searchCriteria={'searchQuery': query, 'memoryStrategyId': config['strategy_id'],
                        'topK': 5})['memoryRecordSummaries']


def verify_scope(items, actor):
    expected = namespace(actor)
    if any(r.get('namespaces') != [expected] for r in items):
        raise RuntimeError('FAIL: returned record belongs to an unexpected namespace')


def denied(label, call, checks):
    try:
        call()
    except ClientError as error:
        code = error.response['Error']['Code']
        if code not in ('AccessDenied', 'AccessDeniedException'):
            raise
        checks.append({'check': label, 'status': 'PASS', 'aws_error': code})
        print('PASS: ' + label + ' denied by AWS', file=sys.stderr, flush=True)
        return
    raise RuntimeError('FAIL: unexpected permission: ' + label)


def ready(base, config):
    memory = base.client('bedrock-agentcore-control', config=OPTIONS).get_memory(
        memoryId=config['memory_id'])['memory']
    strategy = next((s for s in memory.get('strategies', [])
                     if s['strategyId'] == config['strategy_id']), {})
    if (memory['status'] != 'ACTIVE' or strategy.get('status') != 'ACTIVE'
            or strategy.get('type') != 'SEMANTIC'
            or strategy.get('namespaceTemplates', strategy.get('namespaces')) != ['/facts/{actorId}/']):
        raise RuntimeError('Memory/strategy not ready or namespace differs from configuration')


def demo(base, config, wait_seconds):
    ready(base, config)
    sts = base.client('sts', config=OPTIONS)
    checks = []
    common = {'RoleArn': config['role_arn'], 'RoleSessionName': 'invalid-tag-test',
              'DurationSeconds': 900}
    denied('missing TenantId', lambda: sts.assume_role(**common), checks)
    denied('unknown TenantId', lambda: sts.assume_role(**common,
        Tags=[{'Key': 'TenantId', 'Value': 'tenant-c'}]), checks)
    denied('extra tag', lambda: sts.assume_role(**common,
        Tags=[{'Key': 'TenantId', 'Value': 'tenant-a'}, {'Key': 'Extra', 'Value': 'x'}]), checks)
    run = uuid.uuid4().hex[:12]
    session = 'travel-' + run
    actors = {t: t + '_alice_' + run for t in TENANTS}
    sessions = {t: assume(sts, config, t) for t in TENANTS}
    clients = {t: s.client('bedrock-agentcore', config=OPTIONS) for t, s in sessions.items()}
    inputs = json.loads((ROOT / 'data' / 'conversations.json').read_text(encoding='utf-8'))
    result = {'status': 'running', 'memory_id': config['memory_id'],
              'role_arn': config['role_arn'], 'actors': actors, 'session_id': session,
              'checks': checks, 'tenants': {}}
    for tenant, client in clients.items():
        actor = actors[tenant]
        event_id = save(client, config, actor, session, inputs[tenant])
        events = history(client, config, actor, session)
        if not any(e['eventId'] == event_id and any(
                p.get('conversational', {}).get('content', {}).get('text') == inputs[tenant]
                for p in e.get('payload', [])) for e in events):
            raise RuntimeError('Own saved event was not read back: ' + tenant)
        checks.append({'check': tenant + ' own short-term write/read', 'status': 'PASS'})
        result['tenants'][tenant] = {'actor_id': actor, 'namespace': namespace(actor),
            'submitted_text': inputs[tenant], 'event_id': event_id, 'events': events}
        other = actors['tenant-b' if tenant == 'tenant-a' else 'tenant-a']
        denied(tenant + ' cross-tenant write',
               lambda: save(client, config, other, session, 'unauthorized test'), checks)
        denied(tenant + ' cross-tenant history', lambda: history(client, config, other, session), checks)
        denied(tenant + ' cannot retag itself', lambda: sessions[tenant].client('sts', config=OPTIONS).assume_role(
            **common, Tags=[{'Key': 'TenantId', 'Value': 'tenant-b' if tenant == 'tenant-a' else 'tenant-a'}]), checks)
    print(json.dumps({'actors': actors, 'session_id': session}), file=sys.stderr, flush=True)
    start = time.monotonic()
    while True:
        for tenant, client in clients.items():
            result['tenants'][tenant]['records'] = records(client, config, actors[tenant])
            verify_scope(result['tenants'][tenant]['records'], actors[tenant])
        counts = {t: len(result['tenants'][t]['records']) for t in TENANTS}
        print(json.dumps({'elapsed_seconds': round(time.monotonic() - start, 1),
                          'record_counts': counts}), file=sys.stderr, flush=True)
        if all(counts.values()):
            break
        remaining = wait_seconds - (time.monotonic() - start)
        if remaining <= 0:
            result['status'] = 'incomplete_observation'
            return result
        time.sleep(min(20, remaining))
    # Run negative reads after positive evidence that both namespaces exist.
    for tenant, client in clients.items():
        other_tenant = 'tenant-b' if tenant == 'tenant-a' else 'tenant-a'
        other = actors[other_tenant]
        own = retrieve(client, config, actors[tenant], '旅行先と予算')
        verify_scope(own, actors[tenant])
        if not own:
            raise RuntimeError('Own semantic retrieval returned no records: ' + tenant)
        result['tenants'][tenant]['retrieved'] = own
        checks.append({'check': tenant + ' own long-term list/retrieve', 'status': 'PASS'})
        denied(tenant + ' cross-tenant list', lambda: records(client, config, other), checks)
        denied(tenant + ' cross-tenant retrieve', lambda: retrieve(client, config, other, '旅行先と予算'), checks)
        denied(tenant + ' root namespace', lambda: client.list_memory_records(
            memoryId=config['memory_id'], namespace='/'), checks)
        denied(tenant + ' namespacePath cannot bypass', lambda: client.list_memory_records(
            memoryId=config['memory_id'], namespacePath='/facts/'), checks)
        denied(tenant + ' similar tenant prefix', lambda: records(client, config, tenant + '-admin_alice'), checks)
        record_id = result['tenants'][other_tenant]['records'][0]['memoryRecordId']
        denied(tenant + ' direct record ID', lambda: client.get_memory_record(
            memoryId=config['memory_id'], memoryRecordId=record_id), checks)
    result['status'] = 'passed'
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['demo', 'save', 'show'])
    parser.add_argument('--tenant', choices=TENANTS)
    parser.add_argument('--actor')
    parser.add_argument('--session', help='Required for save; optional short-term session for show')
    parser.add_argument('--text', help='Conversation text to save as one USER event')
    parser.add_argument('--wait-seconds', type=int, default=600)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if not 0 <= args.wait_seconds <= 900:
        parser.error('--wait-seconds must be 0-900')
    if args.action in ('save', 'show') and (not args.tenant or not args.actor):
        parser.error(args.action + ' requires --tenant and --actor')
    if args.action == 'save' and (not args.session or not args.text or not args.text.strip()):
        parser.error('save requires --session and non-empty --text')
    if args.action != 'save' and args.text is not None:
        parser.error('--text is only used with save')
    if args.action == 'demo' and any((args.tenant, args.actor, args.session)):
        parser.error('demo automatically creates both tenants and a new actor/session')
    if args.actor:
        namespace(args.actor)
    config = settings()
    base = boto3.Session(profile_name=config['aws_profile'], region_name=config['aws_region'])
    if args.action == 'demo':
        result = demo(base, config, args.wait_seconds)
    else:
        if args.action == 'save':
            ready(base, config)
        client = assume(base.client('sts', config=OPTIONS), config, args.tenant).client('bedrock-agentcore', config=OPTIONS)
        result = {'tenant': args.tenant, 'actor_id': args.actor, 'namespace': namespace(args.actor)}
        if args.action == 'save':
            result.update(status='event_saved', session_id=args.session,
                          event_id=save(client, config, args.actor, args.session, args.text))
        else:
            result['records'] = records(client, config, args.actor)
            verify_scope(result['records'], args.actor)
            if args.session:
                result['events'] = history(client, config, args.actor, args.session)
    result['observed_at'] = datetime.now(timezone.utc).isoformat()
    rendered = json.dumps(result, ensure_ascii=False, indent=2, default=str)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + '\n', encoding='utf-8')
    print(rendered)
    return 2 if result.get('status') == 'incomplete_observation' else 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except ClientError as error:
        raise SystemExit('AWS error: ' + error.response['Error']['Code']) from None
    except (BotoCoreError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from None
