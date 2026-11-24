"""No model: route each message to the persisted current owner."""
import asyncio
import json
import os
import boto3
from botocore.config import Config
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from contracts import request
from store import Store
from transport import call_a2a

app = BedrockAgentCoreApp()


async def route(value, store, call):
    request(value, ('create', 'status', 'talk', 'handoff', 'advance'))
    action, cid = value['action'], value['case_id']
    if action == 'create':
        state = await asyncio.to_thread(store.create, cid, value['mode'], value['notes'])
        return {'state': state}
    state = await asyncio.to_thread(store.get_state, cid)
    if action == 'status': return {'state': state}
    # Repeating a handoff always goes to the predecessor for an idempotent acknowledgment.
    role = 'predecessor' if action in ('handoff', 'advance') else state['owner']
    if role not in ('predecessor', 'successor'): raise ValueError('Unknown owner')
    return await call(role, value)


@app.entrypoint
async def invoke(value):
    session = boto3.Session(region_name=os.environ['SAMPLE_REGION'])
    store = Store(session.resource('dynamodb'), os.environ['STATE_TABLE'], os.environ['PRIVATE_TABLE'])
    api = session.client('bedrock-agentcore', config=Config(read_timeout=240, retries={'total_max_attempts': 1}))
    arns = json.loads(os.environ['WORKER_ARNS'])
    async def call(role, message): return await call_a2a(api, arns[role], message)
    task = app.add_async_task('case-request')
    try: return await route(value, store, call)
    finally: app.complete_async_task(task)


if __name__ == '__main__': app.run()
