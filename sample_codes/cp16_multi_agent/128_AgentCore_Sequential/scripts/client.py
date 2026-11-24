"""Run the deployed pipeline, then read each saved stage from S3."""
import common
import argparse
import json
from pathlib import Path
import uuid

import boto3
from botocore.config import Config
from contracts import STAGES, digest, validate_product
from pipeline import invoke_json


def read_json(s3, bucket, key):
    response = s3.get_object(Bucket=bucket, Key=key)
    try:
        return json.loads(response["Body"].read())
    finally:
        response["Body"].close()


def inspect(session, cfg, run_id):
    if str(uuid.UUID(run_id)) != run_id:
        raise ValueError("Expected canonical run UUID")
    s3, bucket = session.client("s3"), cfg["artifact_bucket"]
    manifest = read_json(s3, bucket, f"runs/{run_id}/manifest.json")
    records = []
    previous = None
    for i, entry in enumerate(manifest["stages"]):
        if entry["stage"] != STAGES[i]:
            raise ValueError("Unexpected stage order")
        value = read_json(s3, bucket, entry["input_key"])
        assert digest(value) == entry["input_sha256"], "Input hash mismatch"
        assert value["previous"] == previous, "Previous output was not passed unchanged"
        assert entry["previous_output_sha256"] == (digest(previous) if previous else None)
        if entry["status"] != "completed":
            print(f"{entry['stage']}: {entry['status']}")
            break
        output = read_json(s3, bucket, entry["output_key"])
        assert output["input_sha256"] == digest(value)
        assert digest(output) == entry["output_sha256"]
        print(f"\n=== {entry['stage']} ({entry['elapsed_seconds']}s) ===\n{output['text']}")
        records.append({"input": value, "output": output})
        previous = output
    if manifest["status"] == "completed":
        assert len(records) == len(STAGES)
        print("\nPASS: saved artifacts prove brief -> copy -> social input/output chain")
    else:
        print("Pipeline incomplete:", manifest.get("error", manifest["status"]))
    print("Saved:", common.save("inspect", {"manifest": manifest, "stages": records}))
    return manifest["status"] == "completed"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("run")
    run.add_argument("--product", type=Path, default=common.ROOT / "product.json")
    show = sub.add_parser("inspect")
    show.add_argument("run_id")
    args = parser.parse_args()
    cfg = common.settings()
    session = boto3.Session(profile_name=cfg["aws_profile"], region_name=cfg["aws_region"])
    if args.command == "run":
        product = json.loads(args.product.read_text(encoding="utf-8"))
        validate_product(product)
        api = session.client("bedrock-agentcore", config=Config(read_timeout=720, retries={"total_max_attempts": 1}))
        print("Running on AWS: brief -> copy -> social", flush=True)
        result = invoke_json(api, cfg["pipeline_arn"], {"product": product})
        print("Saved:", common.save("run", result))
        if "manifest" not in result:
            raise RuntimeError(json.dumps(result, ensure_ascii=False))
        run_id = result["manifest"]["run_id"]
        print("Run ID:", run_id)
        print("Artifacts:", f"s3://{cfg['artifact_bucket']}/runs/{run_id}/")
    else:
        run_id = args.run_id
    return 0 if inspect(session, cfg, run_id) else 1


if __name__ == "__main__":
    raise SystemExit(main())
