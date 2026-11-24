"""Run the AWS comparison and inspect saved evidence."""
import common
import argparse
from datetime import datetime
import json
import uuid
from pathlib import Path
import boto3
from botocore.config import Config
from contracts import SPECIALISTS, digest
from pipeline import invoke_json
from inputs import upload_documents


def read(s3, bucket, key):
    obj = s3.get_object(Bucket=bucket, Key=key)
    try:
        return json.loads(obj["Body"].read())
    finally:
        obj["Body"].close()


def read_partial_results(s3, bucket, manifest):
    """全体が失敗しても、完了済み担当の検証済み出力を取得します。"""
    reports, errors = {}, {}
    for ref in manifest.get("reports", []):
        role = ref["role"]
        try:
            key = f"runs/{manifest['run_id']}/{role}/output.json"
            if role not in SPECIALISTS or ref["key"] != key:
                raise ValueError("Unexpected report reference")
            report = read(s3, bucket, key)
            if (digest(report) != ref["sha256"] or report["role"] != role
                    or report["run_id"] != manifest["run_id"]):
                raise ValueError("Saved report hash or identity mismatch")
            reports[role] = report
        except Exception as exc:
            errors[role] = f"{type(exc).__name__}: {exc}"
    return {
        "status": manifest["status"], "run_id": manifest["run_id"],
        "manifest": manifest, "summary": None,
        "evaluations": {role: report["text"] for role, report in reports.items()},
        "calculations": {role: report.get("calculations", []) for role, report in reports.items()},
        "report_errors": errors,
    }


def verify_records(manifest, records):
    if manifest["status"] != "completed":
        raise ValueError("Run incomplete")
    expected = [*manifest["reports"], manifest["summary"]]
    if {r["role"] for r in expected} != {*SPECIALISTS, "summary"} or len(expected) != 4:
        raise ValueError("Expected three specialists and summary")
    for ref in expected:
        value, report = records[ref["role"]]["input"], records[ref["role"]]["output"]
        if digest(report) != ref["sha256"] or report["input_sha256"] != digest(value):
            raise ValueError("Saved input/output hash mismatch")
        if report["role"] != ref["role"] or report["run_id"] != manifest["run_id"]:
            raise ValueError("Report identity mismatch")
        if ref["role"] != "summary" and set(value) != {"common_markdown", "document_markdown"}:
            raise ValueError("Specialist input must not contain peer reports")
        if digest(value["common_markdown"]) != manifest["input_hashes"]["common"]:
            raise ValueError("Common input differs from uploaded document")
        if ref["role"] != "summary" and digest(value["document_markdown"]) != manifest["input_hashes"][ref["role"]]:
            raise ValueError("Specialist input differs from uploaded document")
    reports = records["summary"]["input"]["reports"]
    if reports != [records[role]["output"] for role in SPECIALISTS]:
        raise ValueError("Summary did not receive exact specialist reports")
    spans = [records[role]["output"] for role in SPECIALISTS]
    overlap = min(datetime.fromisoformat(r["finished_at"]) for r in spans) - max(datetime.fromisoformat(r["started_at"]) for r in spans)
    if datetime.fromisoformat(records["summary"]["output"]["started_at"]) < max(datetime.fromisoformat(r["finished_at"]) for r in spans):
        raise ValueError("Summary started before specialists finished")
    return round(overlap.total_seconds(), 3)


def inspect(session, cfg, run_id):
    if str(uuid.UUID(run_id)) != run_id:
        raise ValueError("Expected canonical UUID")
    s3, bucket = session.client("s3"), cfg["artifact_bucket"]
    manifest = read(s3, bucket, f"runs/{run_id}/manifest.json")
    if manifest["status"] != "completed":
        result = read_partial_results(s3, bucket, manifest)
        for role, text in result["evaluations"].items():
            print(f"\n=== {role} (completed) ===\n{text}")
        print(json.dumps(manifest, ensure_ascii=False, indent=2))
        if result["report_errors"]:
            print("Report retrieval errors:", json.dumps(result["report_errors"], ensure_ascii=False))
        print("Saved:", common.save("inspect", result))
        return False
    records = {}
    for role in (*SPECIALISTS, "summary"):
        base = f"runs/{run_id}/{role}"
        records[role] = {kind: read(s3, bucket, base + f"/{kind}.json") for kind in ("input", "output")}
        report = records[role]["output"]
        print(f"\n=== {role}: {report['elapsed_seconds']}s ===\n{report['text']}")
        for calculation in report.get("calculations", []):
            print(f"  calculate [{calculation['purpose']}]: {calculation['expression']} = {calculation['result']}")
    overlap = verify_records(manifest, records)
    print("PASS: independent inputs, saved hashes and exact reports handed to summary")
    print(f"{'PASS' if overlap > 0 else 'INCONCLUSIVE'}: specialist execution overlap = {overlap}s")
    print("Saved:", common.save("inspect", {"manifest": manifest, "records": records, "overlap_seconds": overlap}))
    return True


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("run").add_argument("--input-dir", type=Path, default=common.ROOT / "properties")
    sub.add_parser("inspect").add_argument("run_id")
    args = p.parse_args()
    cfg = common.settings()
    session = boto3.Session(profile_name=cfg["aws_profile"], region_name=cfg["aws_region"])
    if args.command == "run":
        api = session.client("bedrock-agentcore", config=Config(read_timeout=600, retries={"total_max_attempts": 1}))
        print("Running: (cost || commute || environment) -> summary", flush=True)
        payload = upload_documents(session.client("s3"), cfg["artifact_bucket"], args.input_dir)
        print("Uploaded Markdown; Run ID:", payload["run_id"], flush=True)
        common.save("upload", payload)
        result = invoke_json(api, cfg["pipeline_arn"], payload)
        print("Saved:", common.save("run", result))
        if "manifest" not in result:
            raise RuntimeError(json.dumps(result, ensure_ascii=False))
        run_id = result["manifest"]["run_id"]
    else:
        run_id = args.run_id
    print("Run ID:", run_id)
    print("Artifacts:", f"s3://{cfg['artifact_bucket']}/runs/{run_id}/")
    return 0 if inspect(session, cfg, run_id) else 1


if __name__ == "__main__":
    raise SystemExit(main())
