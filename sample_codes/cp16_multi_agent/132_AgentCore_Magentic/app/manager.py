import asyncio
import json
import os
import boto3
from botocore.config import Config
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from contracts import manager_request
from model import build_model, generate
from orchestration import advance, now
from store import Store
from transport import call_a2a_with_trace

app = BedrockAgentCoreApp()


async def handle(value, store, call, respond):
    manager_request(value)
    cid, action = value['case_id'], value['action']
    if action == 'create':
        state = await asyncio.to_thread(store.create, {'case_id': cid, 'scenario': value['scenario'],
            'request': value['request'], 'created_at': now(), 'owner': 'dealer', 'revision': 0,
            'phase': 'planning', 'plans': [], 'observations': [], 'active_seconds': 0})
        if state['revision'] == 0: state = await advance(state, store, call, respond)
    else:
        state = await asyncio.to_thread(store.get, cid)
        if action == 'advance':
            if value['expected_revision'] != state['revision']: return {'state': state, 'stale_request': True}
            state = await advance(state, store, call, respond)
    return {'state': state}


@app.entrypoint
async def invoke(value):
    session = boto3.Session(region_name=os.environ['SAMPLE_REGION'])
    store = Store(session.resource('dynamodb').Table(os.environ['STATE_TABLE']))
    api = session.client('bedrock-agentcore', config=Config(read_timeout=170, retries={'total_max_attempts': 1}))
    model = build_model(session, os.environ['MODEL_ID'])
    arns = json.loads(os.environ['SPECIALIST_ARNS'])
    async def call(role, query): return await call_a2a_with_trace(api, arns[role], query)
    async def respond(prompt, query): return await generate(model, prompt, query)
    task = app.add_async_task('dealer-coordination')
    try:
        async with asyncio.timeout(290): return await handle(value, store, call, respond)
    finally: app.complete_async_task(task)


if __name__ == '__main__': app.run()
