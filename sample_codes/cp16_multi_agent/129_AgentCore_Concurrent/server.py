"""AWS上の処理を呼び出すローカルHTTP MCPサーバー。"""
import asyncio
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent / "scripts"))
import common
import boto3
from botocore.config import Config
from fastmcp import FastMCP
from client import read, read_partial_results, verify_records
from contracts import SPECIALISTS
from pipeline import invoke_json
from inputs import upload_documents
from pathlib import Path

mcp = FastMCP("AgentCore concurrent rental comparison")


def run_remote(input_dir="properties"):
    cfg = common.settings()
    session = boto3.Session(profile_name=cfg["aws_profile"], region_name=cfg["aws_region"])
    api = session.client("bedrock-agentcore", config=Config(read_timeout=600, retries={"total_max_attempts": 1}))
    folder = Path(input_dir)
    if not folder.is_absolute():
        folder = common.ROOT / folder
    payload = upload_documents(session.client("s3"), cfg["artifact_bucket"], folder)
    common.save("mcp-upload", payload)
    result = invoke_json(api, cfg["pipeline_arn"], payload)
    path = common.save("mcp-run", result)
    manifest = result.get("manifest")
    if not manifest:
        raise RuntimeError(f"Unexpected Runtime response; see {path}")
    if manifest["status"] != "completed":
        partial = read_partial_results(session.client("s3"), cfg["artifact_bucket"], manifest)
        path = common.save("mcp-partial", partial)
        return {**partial, "result_file": str(path)}
    s3, bucket = session.client("s3"), cfg["artifact_bucket"]
    records = {}
    for role in (*SPECIALISTS, "summary"):
        base = f"runs/{manifest['run_id']}/{role}"
        records[role] = {kind: read(s3, bucket, base + f"/{kind}.json") for kind in ("input", "output")}
    overlap = verify_records(manifest, records)
    path = common.save("mcp-evidence", {"manifest": manifest, "records": records, "overlap_seconds": overlap})
    return {"status": "completed", "run_id": manifest["run_id"], "model_id": cfg["model_id"],
            "evaluations": {role: records[role]["output"]["text"] for role in SPECIALISTS},
            "summary": records["summary"]["output"]["text"], "overlap_seconds": overlap,
            "calculations": {role: records[role]["output"]["calculations"] for role in SPECIALISTS},
            "parallel_observation": "observed" if overlap > 0 else "inconclusive",
            "artifact_verification": "passed", "result_file": str(path)}


@mcp.tool()
async def compare_rentals(input_dir: str = "properties") -> dict:
    """Run this sample once: compare three fictional rentals on AWS.

    AWS Runtime independently evaluates cost, commute and environment, then synthesizes them.
    Uploads common.md, cost.md, commute.md and environment.md from input_dir to AWS S3.
    Relative paths resolve inside this sample. Default properties contains fictional examples.
    Use only the directory the user requests; do not search or upload unrelated files.
    Creates a fresh run and saves input documents, calculations and reports.
    Returns specialist opinions, the remote summary and execution evidence. May take minutes.
    If the run fails, display completed evaluations and the error; summary is unavailable.
    Do not automatically retry a failed or incomplete run. No booking or infrastructure changes.
    """
    return await asyncio.to_thread(run_remote, input_dir)


if __name__ == "__main__":
    mcp.run(transport="http", host="127.0.0.1", port=8000, path="/mcp")
