"""Compare AWS-generated records without rewriting or summarizing their content."""
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


def settings():
    result = subprocess.run(['terraform', 'output', '-json', 'client_config'], cwd=ROOT / 'terraform',
                            capture_output=True, text=True, encoding='utf-8', check=True)
    return json.loads(result.stdout)


def aws_clients(config):
    aws = boto3.Session(profile_name=config['aws_profile'], region_name=config['aws_region'])
    options = Config(connect_timeout=10, read_timeout=30,
                     retries={'mode': 'standard', 'total_max_attempts': 3})
    return aws.client('bedrock-agentcore', config=options), aws.client('bedrock-agentcore-control', config=options)


def ready(control, config):
    memory = control.get_memory(memoryId=config['memory_id'])['memory']
    actual = {s['strategyId']: s for s in memory.get('strategies', [])}
    if memory['status'] != 'ACTIVE':
        raise RuntimeError('Memory is not ACTIVE; no conversation was submitted')
    for strategy in config['strategies'].values():
        found = actual.get(strategy['id'], {})
        if found.get('status') != 'ACTIVE' or found.get('type') != strategy['type']:
            raise RuntimeError('A configured strategy is not ACTIVE or has a different type')
        if found.get('namespaceTemplates', found.get('namespaces')) != [strategy['namespace']]:
            raise RuntimeError('Strategy namespace differs from Terraform configuration')


def namespace(strategy, actor, session):
    for value in (actor, session):
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', value):
            raise ValueError('Actor/session must contain 1-80 letters, digits, underscores or hyphens')
    return strategy['namespace'].replace('{actorId}', actor).replace('{sessionId}', session)


def submit(client, config, actor, session, turns):
    response = client.create_event(memoryId=config['memory_id'], actorId=actor, sessionId=session,
        eventTimestamp=datetime.now(timezone.utc), clientToken=str(uuid.uuid4()),
        payload=[{'conversational': {'role': t['role'], 'content': {'text': t['text']}}} for t in turns])
    return response['event']['eventId']


def snapshot(client, config, actor, session):
    result = {}
    for label, strategy in config['strategies'].items():
        path = namespace(strategy, actor, session)
        records = []
        for page in client.get_paginator('list_memory_records').paginate(
                memoryId=config['memory_id'], namespace=path, memoryStrategyId=strategy['id']):
            records.extend(page['memoryRecordSummaries'])
        # Preserve every API record and its content. Sort only for readable diffs.
        records.sort(key=lambda r: (str(r.get('createdAt', '')), r['memoryRecordId']))
        result[label] = {'strategy_id': strategy['id'], 'type': strategy['type'],
                         'namespace': path, 'records': records}
    return result


def observe(client, config, actor, session, wait_seconds):
    start = time.monotonic()
    while True:
        result = snapshot(client, config, actor, session)
        counts = {label: len(item['records']) for label, item in result.items()}
        print(json.dumps({'elapsed_seconds': round(time.monotonic() - start, 1), 'record_counts': counts}),
              file=sys.stderr, flush=True)
        if all(counts.values()):
            return 'records_observed', result
        remaining = wait_seconds - (time.monotonic() - start)
        if remaining <= 0:
            return 'incomplete_observation', result
        time.sleep(min(20, remaining))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['demo', 'show'])
    parser.add_argument('--actor', help='show requires the actor ID printed by demo')
    parser.add_argument('--session', default='travel-001')
    parser.add_argument('--wait-seconds', type=int, default=600)
    parser.add_argument('--output', type=Path, help='Optional UTF-8 snapshot file; never used as a read cache')
    args = parser.parse_args()
    if not 0 <= args.wait_seconds <= 900:
        parser.error('--wait-seconds must be from 0 to 900')
    if args.action == 'show' and not args.actor:
        parser.error('show requires --actor')
    if args.action == 'demo' and args.actor:
        parser.error('demo always creates a fresh actor; use show --actor to inspect an existing run')
    actor = args.actor or 'demo-' + uuid.uuid4().hex
    config = settings()
    for strategy in config['strategies'].values():
        namespace(strategy, actor, args.session)
    client, control = aws_clients(config)
    ready(control, config)
    event_id = None
    turns = None
    if args.action == 'demo':
        # A fresh actor prevents old actor-scoped records from passing readiness.
        if any(s['records'] for s in snapshot(client, config, actor, args.session).values()):
            raise RuntimeError('Actor already has long-term records; use a fresh actor or show')
        if any(page['events'] for page in client.get_paginator('list_events').paginate(
                memoryId=config['memory_id'], actorId=actor, sessionId=args.session, includePayloads=False)):
            raise RuntimeError('Session already has events; use show instead of submitting again')
        turns = json.loads((ROOT / 'data' / 'conversation.json').read_text(encoding='utf-8'))
        event_id = submit(client, config, actor, args.session, turns)
    print(json.dumps({'memory_id': config['memory_id'], 'actor_id': actor,
                      'session_id': args.session, 'event_id': event_id}), file=sys.stderr, flush=True)
    status, strategies = observe(client, config, actor, args.session, args.wait_seconds)
    result = {'observed_at': datetime.now(timezone.utc).isoformat(), 'status': status,
              'memory_id': config['memory_id'], 'actor_id': actor, 'session_id': args.session,
              'event_id': event_id, 'submitted_conversation': turns, 'strategies': strategies,
              'note': 'Presence is not proof of extraction completion or semantic accuracy. Content is unmodified.'}
    rendered = json.dumps(result, ensure_ascii=False, indent=2, default=str)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + '\n', encoding='utf-8')
    print(rendered)
    return 0 if status == 'records_observed' else 2


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except ClientError as error:
        raise SystemExit('AWS error: ' + error.response['Error']['Code']) from None
    except (BotoCoreError, subprocess.CalledProcessError, FileNotFoundError) as error:
        raise SystemExit(type(error).__name__ + ': check SSO, Terraform deployment, input file and PATH') from None
    except (RuntimeError, ValueError) as error:
        raise SystemExit(str(error)) from None
