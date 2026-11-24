import asyncio
import json
import uuid
from contracts import encoded, request_rpc, extract_rpc


def invoke_json(api, arn, value):
    response = api.invoke_agent_runtime(agentRuntimeArn=arn, qualifier="DEFAULT",
        runtimeSessionId=str(uuid.uuid4()), contentType="application/json", payload=encoded(value))
    try: return json.loads(response["response"].read())
    finally: response["response"].close()


async def call_a2a(api, arn, value):
    request_id = str(uuid.uuid4())
    return extract_rpc(await asyncio.to_thread(invoke_json, api, arn, request_rpc(value, request_id)), request_id)


async def call_a2a_with_trace(api, arn, value):
    request_id = str(uuid.uuid4())
    response = await asyncio.to_thread(invoke_json, api, arn, request_rpc(value, request_id))
    result = extract_rpc(response, request_id)
    return {'result': result, 'a2a': {'request_id': request_id,
        'task_id': response['result']['id'], 'context_id': response['result'].get('contextId'),
        'target_runtime': arn}}
