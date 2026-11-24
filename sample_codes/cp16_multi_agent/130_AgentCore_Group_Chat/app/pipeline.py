"""Bounded round-robin meeting chair: no LLM-based speaker selection."""
import asyncio
from datetime import datetime, timezone
import json
import os
import uuid
import boto3
from botocore.config import Config
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from contracts import SCHEDULE, digest, encoded, extract_rpc, output_key, request_rpc, validate_inputs, validate_history
from memory import Journal

app = BedrockAgentCoreApp()


def now(): return datetime.now(timezone.utc).isoformat()


def invoke_json(api, arn, payload):
    response = api.invoke_agent_runtime(agentRuntimeArn=arn, qualifier="DEFAULT", runtimeSessionId=str(uuid.uuid4()),
                                        contentType="application/json", payload=encoded(payload))
    try: return json.loads(response["response"].read())
    finally: response["response"].close()


async def run_meeting(payload, call, save, journal):
    run_id = validate_inputs(payload)
    manifest = {**payload, "status": "running", "started_at": now(), "turns": []}
    key = f"runs/{run_id}/manifest.json"
    await save(key, manifest)
    try:
        for turn, role in enumerate(SCHEDULE, 1):
            history = await journal.load(manifest["turns"])
            validate_history(history, turn)
            names = ("common",) if role == "summary" else ("common", role)
            request = {"run_id": run_id, "role": role, "turn": turn, "history": history,
                       "input_hashes": {n: payload["input_hashes"][n] for n in names}}
            result = await call(role, request)
            if (result["run_id"] != run_id or result["role"] != role or result["turn"] != turn
                    or result["key"] != output_key(run_id, role, turn) or result["history_sha256"] != digest(history)):
                raise ValueError("Unexpected speaker output/provenance")
            utterance = {"turn": turn, "role": role, "text": result["text"]}
            validate_history([*history, utterance], turn+1)
            event_id = await journal.append(utterance)
            manifest["turns"].append({**result, "event_id": event_id, "utterance_sha256": digest(utterance)})
            await save(key, manifest)
        # Also verify the final summary was actually stored and can be read back.
        await journal.load(manifest["turns"])
        manifest.update(status="completed", stop_reason="two_rounds_then_summary")
    except Exception as exc:
        manifest.update(status="failed", error=f"{type(exc).__name__}: {exc}")
    manifest["finished_at"] = now()
    await save(key, manifest)
    return {"manifest": manifest}


@app.entrypoint
async def invoke(payload):
    run_id = validate_inputs(payload)
    session = boto3.Session(region_name=os.environ["SAMPLE_REGION"])
    api = session.client("bedrock-agentcore", config=Config(read_timeout=180, retries={"total_max_attempts": 1}))
    s3 = session.client("s3")
    arns = json.loads(os.environ["WORKER_ARNS"])
    async def call(role, value):
        request_id = str(uuid.uuid4())
        return extract_rpc(await asyncio.to_thread(invoke_json, api, arns[role], request_rpc(value, request_id)), request_id)
    async def save(key, value):
        await asyncio.to_thread(s3.put_object, Bucket=os.environ["ARTIFACT_BUCKET"], Key=key,
                                Body=encoded(value), ContentType="application/json")
    task_id = app.add_async_task("menu-meeting", {"run_id": run_id})
    try:
        return await run_meeting(payload, call, save, Journal(api, os.environ["MEMORY_ID"], run_id))
    finally:
        app.complete_async_task(task_id)


if __name__ == "__main__": app.run()
