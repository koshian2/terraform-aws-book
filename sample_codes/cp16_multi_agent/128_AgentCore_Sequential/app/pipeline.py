"""Fixed sequential orchestration; no LLM decides the next role."""
import asyncio
from datetime import datetime, timezone
import json
import os
import time
import uuid

import boto3
from botocore.config import Config
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from contracts import STAGES, digest, encoded, validate_output, validate_product

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


def a2a_result(response, request_id):
    if response.get("jsonrpc") != "2.0" or response.get("id") != request_id:
        raise ValueError("Unexpected A2A response envelope")
    if "error" in response:
        raise RuntimeError("A2A JSON-RPC error: " + json.dumps(response["error"], ensure_ascii=False))
    task = response.get("result", {})
    if task.get("status", {}).get("state") != "completed":
        raise RuntimeError("A2A task not completed: " + json.dumps(task.get("status"), ensure_ascii=False))
    data = [p["data"] for a in task.get("artifacts", []) for p in a.get("parts", []) if p.get("kind") == "data"]
    if len(data) != 1:
        raise ValueError("Expected exactly one A2A data artifact")
    return data[0], task["id"]


async def run_pipeline(product, call_stage, save):
    validate_product(product)
    run_id = str(uuid.uuid4())
    prefix = f"runs/{run_id}"
    manifest = {"run_id": run_id, "status": "running", "started_at": now(), "stages": []}
    await save(f"{prefix}/00-product.json", product)
    await save(f"{prefix}/manifest.json", manifest)
    previous = None
    try:
        for index, stage in enumerate(STAGES, 1):
            value = {"run_id": run_id, "stage": stage, "product": product, "previous": previous}
            base = f"{prefix}/{index:02d}-{stage}"
            entry = {"stage": stage, "status": "running", "started_at": now(),
                     "input_key": base + "/input.json", "output_key": base + "/output.json",
                     "input_sha256": digest(value), "previous_output_sha256": digest(previous) if previous else None}
            manifest["stages"].append(entry)
            await save(entry["input_key"], value)
            await save(f"{prefix}/manifest.json", manifest)
            start = time.monotonic()
            output, task_id = await call_stage(stage, value)
            validate_output(output, stage, entry["input_sha256"])
            await save(entry["output_key"], output)
            entry.update(status="completed", finished_at=now(), elapsed_seconds=round(time.monotonic()-start, 3),
                         task_id=task_id, output_sha256=digest(output))
            await save(f"{prefix}/manifest.json", manifest)
            print(json.dumps({"event": "stage_completed", "run_id": run_id, "stage": stage,
                              "task_id": task_id, "elapsed_seconds": entry["elapsed_seconds"]}), flush=True)
            previous = output
        manifest["status"] = "completed"
    except Exception as exc:
        manifest["status"] = "failed"
        if manifest["stages"]:
            manifest["stages"][-1]["status"] = "failed"
        manifest["error"] = f"{type(exc).__name__}: {exc}"
    manifest["finished_at"] = now()
    await save(f"{prefix}/manifest.json", manifest)
    return {"manifest": manifest, "manifest_key": f"{prefix}/manifest.json",
            "final": previous if manifest["status"] == "completed" else None}


@app.entrypoint
async def invoke(payload):
    region = os.environ["SAMPLE_REGION"]
    arns = json.loads(os.environ["WORKER_ARNS"])
    bucket = os.environ["ARTIFACT_BUCKET"]
    api = boto3.client("bedrock-agentcore", region_name=region,
                       config=Config(read_timeout=180, retries={"total_max_attempts": 1}))
    s3 = boto3.client("s3", region_name=region)

    async def save(key, value):
        await asyncio.to_thread(s3.put_object, Bucket=bucket, Key=key, Body=encoded(value), ContentType="application/json")

    async def call(stage, value):
        request_id = str(uuid.uuid4())
        request = {"jsonrpc": "2.0", "id": request_id, "method": "message/send", "params": {
            "message": {"role": "user", "messageId": str(uuid.uuid4()),
                        "parts": [{"kind": "text", "text": encoded(value).decode()}]},
            "configuration": {"blocking": True}}}
        response = await asyncio.to_thread(invoke_json, api, arns[stage], request)
        return a2a_result(response, request_id)

    async with asyncio.timeout(660):
        result = await run_pipeline(payload.get("product"), call, save)
    return {**result, "artifact_bucket": bucket}


if __name__ == "__main__":
    app.run()
