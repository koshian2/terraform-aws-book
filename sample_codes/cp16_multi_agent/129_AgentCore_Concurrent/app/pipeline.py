"""Fixed fan-out/fan-in orchestration on Runtime; no model in the coordinator."""
import asyncio
from datetime import datetime, timezone
import json
import os
import uuid

import boto3
from botocore.config import Config
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from contracts import SPECIALISTS, encoded, extract_rpc, request_rpc, validate_inputs

app = BedrockAgentCoreApp()


def now():
    return datetime.now(timezone.utc).isoformat()


def invoke_json(api, arn, payload):
    response = api.invoke_agent_runtime(agentRuntimeArn=arn, qualifier="DEFAULT",
        runtimeSessionId=str(uuid.uuid4()), contentType="application/json", payload=encoded(payload))
    try:
        return json.loads(response["response"].read())
    finally:
        response["response"].close()


async def run_pipeline(call, save, payload):
    run_id = validate_inputs(payload)
    manifest = {"run_id": run_id, "input_hashes": payload["input_hashes"], "status": "running", "started_at": now(), "calls": [], "reports": []}
    key = f"runs/{run_id}/manifest.json"
    await save(key, manifest)

    async def dispatch(role, reports=None):
        entry = {"role": role, "started_at": now(), "status": "running"}
        manifest["calls"].append(entry)
        names = ("common",) if role == "summary" else ("common", role)
        request = {"run_id": run_id, "role": role, "input_hashes": {n: payload["input_hashes"][n] for n in names}}
        if reports is not None:
            request["reports"] = reports
        try:
            ref = await call(role, request)
            if (ref["run_id"] != run_id or ref["role"] != role
                    or ref["key"] != f"runs/{run_id}/{role}/output.json"):
                raise ValueError("Unexpected report reference")
            entry["status"] = "completed"
            return ref
        except Exception as exc:
            entry.update(status="failed", error=f"{type(exc).__name__}: {exc}")
            raise
        finally:
            entry["finished_at"] = now()

    # Wait for all branches, including when one fails. Never summarize partial results.
    results = await asyncio.gather(*(dispatch(role) for role in SPECIALISTS), return_exceptions=True)
    manifest["reports"] = [r for r in results if not isinstance(r, BaseException)]
    if any(isinstance(r, BaseException) for r in results):
        manifest.update(status="failed", error="At least one specialist failed; summary was not invoked")
    else:
        try:
            manifest["summary"] = await dispatch("summary", manifest["reports"])
            manifest["status"] = "completed"
        except Exception as exc:
            manifest.update(status="failed", error=f"{type(exc).__name__}: {exc}")
    manifest["finished_at"] = now()
    await save(key, manifest)
    return {"manifest": manifest}


@app.entrypoint
async def invoke(payload):
    validate_inputs(payload)
    session = boto3.Session(region_name=os.environ["SAMPLE_REGION"])
    api = session.client("bedrock-agentcore", config=Config(read_timeout=240, retries={"total_max_attempts": 1}))
    s3 = session.client("s3")
    arns = json.loads(os.environ["WORKER_ARNS"])

    async def call(role, request):
        request_id = str(uuid.uuid4())
        response = await asyncio.to_thread(invoke_json, api, arns[role], request_rpc(request, request_id))
        return extract_rpc(response, request_id)

    async def save(key, value):
        await asyncio.to_thread(s3.put_object, Bucket=os.environ["ARTIFACT_BUCKET"], Key=key,
                                Body=encoded(value), ContentType="application/json")

    return await run_pipeline(call, save, payload)


if __name__ == "__main__":
    app.run()
