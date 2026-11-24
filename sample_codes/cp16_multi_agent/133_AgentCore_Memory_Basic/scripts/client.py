"""Save and read short-term events directly through the AWS SDK."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import uuid

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

ROOT = Path(__file__).resolve().parents[1]
ACTOR = 'alice'


def settings():
    result = subprocess.run(['terraform', 'output', '-json', 'client_config'],
                            cwd=ROOT / 'terraform', capture_output=True, text=True, encoding='utf-8', check=True)
    return json.loads(result.stdout)


def connect(config):
    return boto3.Session(profile_name=config['aws_profile'], region_name=config['aws_region']).client(
        'bedrock-agentcore', config=Config(connect_timeout=10, read_timeout=30,
                                         retries={'mode': 'standard', 'total_max_attempts': 3}))


def save(client, memory_id, session, text):
    response = client.create_event(
        memoryId=memory_id, actorId=ACTOR, sessionId=session,
        clientToken=str(uuid.uuid4()),
        eventTimestamp=datetime.now(timezone.utc),
        payload=[{'conversational': {'role': 'USER', 'content': {'text': text}}}],
    )
    return response['event']


def history(client, memory_id, session):
    events = []
    for page in client.get_paginator('list_events').paginate(
            memoryId=memory_id, actorId=ACTOR, sessionId=session, includePayloads=True):
        events.extend(page['events'])
    return sorted(events, key=lambda e: (e['eventTimestamp'], e['eventId']))


def conversation(events, text):
    """Convert raw text events to Converse messages, merging adjacent roles."""
    messages = []
    for event in events:
        for payload in event.get('payload', []):
            item = payload.get('conversational', {})
            role = item.get('role', '').lower()
            value = item.get('content', {}).get('text')
            if role not in ('user', 'assistant') or not isinstance(value, str):
                raise RuntimeError('This demo supports only USER/ASSISTANT text history')
            if messages and messages[-1]['role'] == role:
                messages[-1]['content'][0]['text'] += '\n\n' + value
            else:
                messages.append({'role': role, 'content': [{'text': value}]})
    if messages and messages[0]['role'] != 'user':
        raise RuntimeError('Conversation must begin with a USER message')
    if messages and messages[-1]['role'] == 'user':
        messages[-1]['content'][0]['text'] += '\n\n' + text
    else:
        messages.append({'role': 'user', 'content': [{'text': text}]})
    if sum(len(m['content'][0]['text']) for m in messages) > 30000:
        raise RuntimeError('Demo history exceeds 30000 characters; use a new session')
    return messages


def chat(client, model, memory_id, session, text, model_id, show_context=False):
    events = history(client, memory_id, session)
    messages = conversation(events, text)
    if show_context:
        print(json.dumps({'messages_sent_to_model': messages}, ensure_ascii=False, indent=2), file=sys.stderr)
    response = model.converse(modelId=model_id, messages=messages,
        system=[{'text': 'Respond in Japanese. Use the conversation history when relevant. '
                         'If information is absent, say you do not know; do not invent past conversation.'}],
        inferenceConfig={'maxTokens': 2048, 'temperature': 0})
    output = response['output']['message']
    answer = '\n'.join(block['text'] for block in output['content'] if 'text' in block)
    if not answer.strip():
        raise RuntimeError('Model returned no text; no new event was saved')
    # One event contains the complete turn, in USER -> ASSISTANT order.
    try:
        saved = client.create_event(memoryId=memory_id, actorId=ACTOR, sessionId=session,
            clientToken=str(uuid.uuid4()), eventTimestamp=datetime.now(timezone.utc),
            payload=[{'conversational': {'role': role, 'content': {'text': value}}}
                     for role, value in [('USER', text), ('ASSISTANT', answer)]])
    except (ClientError, BotoCoreError):
        print(json.dumps({'answer': answer, 'status': 'memory_save_failed_or_unconfirmed'},
                         ensure_ascii=False), file=sys.stderr)
        raise
    return {'memory_id': memory_id, 'actor_id': ACTOR, 'session_id': session,
            'model_id': model_id, 'history_event_ids': [e['eventId'] for e in events],
            'answer': answer, 'event_id': saved['event']['eventId'], 'status': 'saved',
            'stop_reason': response.get('stopReason')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    store = commands.add_parser('save', help='Write a USER message to Memory')
    store.add_argument('--session', required=True)
    store.add_argument('--text', required=True)
    read = commands.add_parser('history', help='Read all events in a session')
    read.add_argument('--session', required=True)
    talk = commands.add_parser('chat', help='Restore history, call Bedrock, and save the new turn')
    talk.add_argument('--session', required=True)
    talk.add_argument('--text', required=True)
    talk.add_argument('--model-id', help='Override the model configured by Terraform')
    talk.add_argument('--show-context', action='store_true', help='Print exact model messages to stderr')
    args = parser.parse_args()
    if args.command in ('save', 'chat') and not args.text.strip():
        parser.error('--text must not be empty')
    config = settings()
    client = connect(config)
    if args.command == 'save':
        event = save(client, config['memory_id'], args.session, args.text)
        result = {'memory_id': config['memory_id'], 'actor_id': ACTOR, 'session_id': args.session,
                  'event_id': event['eventId'], 'status': 'saved'}
    elif args.command == 'chat':
        model = boto3.Session(profile_name=config['aws_profile'], region_name=config['aws_region']).client(
            'bedrock-runtime', config=Config(connect_timeout=10, read_timeout=60,
                                            retries={'total_max_attempts': 1}))
        result = chat(client, model, config['memory_id'], args.session, args.text,
                      args.model_id or config['model_id'], args.show_context)
    else:
        result = {'memory_id': config['memory_id'], 'actor_id': ACTOR, 'session_id': args.session,
                  'events': history(client, config['memory_id'], args.session)}
    print(json.dumps(result, ensure_ascii=False, indent=2, default=str))


if __name__ == '__main__':
    try:
        main()
    except ClientError as error:
        raise SystemExit('AWS error: ' + error.response['Error']['Code']) from None
    except RuntimeError as error:
        raise SystemExit(str(error)) from None
    except (BotoCoreError, subprocess.CalledProcessError, FileNotFoundError) as error:
        raise SystemExit(type(error).__name__ + ': check AWS SSO, Terraform deployment and PATH') from None
