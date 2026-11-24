"""Upload meeting briefs, run the AWS meeting and inspect its conversation."""
import common
import argparse
import asyncio
import json
from pathlib import Path
import uuid
import boto3
from botocore.config import Config
from contracts import SCHEDULE, digest, output_key
from inputs import upload_documents
from memory import Journal
from pipeline import invoke_json


def read(s3, bucket, key):
    obj = s3.get_object(Bucket=bucket, Key=key)
    try: return json.loads(obj["Body"].read())
    finally: obj["Body"].close()


def verify_records(manifest, records, history):
    if manifest["status"] != "completed" or len(records) != len(SCHEDULE) or len(history) != len(SCHEDULE):
        raise ValueError("Meeting incomplete")
    for index, (ref, record) in enumerate(zip(manifest["turns"], records)):
        value, report = record["input"], record["output"]
        turn, role = index+1, SCHEDULE[index]
        if ref["key"] != output_key(manifest["run_id"], role, turn): raise ValueError("Unexpected output path")
        if report["run_id"] != manifest["run_id"] or report["turn"] != turn or report["role"] != role:
            raise ValueError("Unexpected speaker")
        if digest(report) != ref["sha256"] or report["input_sha256"] != digest(value):
            raise ValueError("Saved input/output hash mismatch")
        if value["history"] != history[:index] or report["history_sha256"] != digest(history[:index]):
            raise ValueError("Speaker did not receive exact preceding conversation")
        if history[index] != {"turn": turn, "role": role, "text": report["text"]}:
            raise ValueError("Memory differs from speaker output")
        if digest(value["common_markdown"]) != manifest["input_hashes"]["common"]:
            raise ValueError("Common brief mismatch")
        expected = {"turn", "history", "common_markdown"}
        if role != "summary":
            expected.add("private_markdown")
            if digest(value["private_markdown"]) != manifest["input_hashes"][role]:
                raise ValueError("Private brief mismatch")
        if set(value) != expected: raise ValueError("Unexpected speaker input")


def inspect(session, cfg, run_id):
    if str(uuid.UUID(run_id)) != run_id: raise ValueError("Expected run UUID")
    s3, bucket = session.client("s3"), cfg["artifact_bucket"]
    manifest = read(s3, bucket, f"runs/{run_id}/manifest.json")
    records = []
    for ref in manifest["turns"]:
        records.append({"input": read(s3, bucket, ref["key"].replace("-output.json", "-input.json")),
                        "output": read(s3, bucket, ref["key"])})
        print(f"\n=== {ref['turn']}: {ref['role']} ===\n{records[-1]['output']['text']}")
    history = asyncio.run(Journal(session.client("bedrock-agentcore"), cfg["memory_id"], run_id).load(manifest["turns"]))
    print("Saved:", common.save("inspect", {"manifest": manifest, "records": records, "memory_history": history}))
    if manifest["status"] != "completed":
        print("FAILED:", manifest.get("error", manifest["status"]))
        return False
    verify_records(manifest, records, history)
    print("PASS: seven turns, exact shared history from Memory, private briefs and saved hashes")
    return True


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("run").add_argument("--input-dir", type=Path, default=common.ROOT / "briefs")
    sub.add_parser("inspect").add_argument("run_id")
    args = p.parse_args()
    cfg = common.settings()
    session = boto3.Session(profile_name=cfg["aws_profile"], region_name=cfg["aws_region"])
    if args.command == "run":
        payload = upload_documents(session.client("s3"), cfg["artifact_bucket"], args.input_dir)
        print("Uploaded briefs; Run ID:", payload["run_id"], flush=True)
        common.save("upload", payload)
        api = session.client("bedrock-agentcore", config=Config(read_timeout=1200, retries={"total_max_attempts": 1}))
        result = invoke_json(api, cfg["pipeline_arn"], payload)
        print("Saved:", common.save("run", result))
        if "manifest" not in result: raise RuntimeError(json.dumps(result, ensure_ascii=False))
        run_id = result["manifest"]["run_id"]
    else: run_id = args.run_id
    return 0 if inspect(session, cfg, run_id) else 1


if __name__ == "__main__": raise SystemExit(main())
