"""AWS上の処理を呼び出すローカルHTTP MCPサーバー。"""
import asyncio
from pathlib import Path
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent / "scripts"))
import common
import boto3
from botocore.config import Config
from fastmcp import FastMCP
from client import read, verify_records
from inputs import upload_documents
from memory import Journal
from pipeline import invoke_json

mcp = FastMCP("AgentCore Group Chat menu meeting")


def run_remote(input_dir):
    folder = Path(input_dir)
    if not folder.is_absolute():
        folder = common.ROOT / folder
    cfg = common.settings()
    session = boto3.Session(profile_name=cfg["aws_profile"], region_name=cfg["aws_region"])
    s3 = session.client("s3")
    payload = upload_documents(s3, cfg["artifact_bucket"], folder)
    common.save("mcp-upload", payload)
    api = session.client("bedrock-agentcore", config=Config(read_timeout=1200, retries={"total_max_attempts": 1}))
    result = invoke_json(api, cfg["pipeline_arn"], payload)
    path = common.save("mcp-run", result)
    manifest = result.get("manifest")
    if not manifest:
        raise RuntimeError(f"Unexpected Runtime response; see {path}")
    if manifest["status"] != "completed":
        return {"status": manifest["status"], "manifest": manifest, "result_file": str(path)}
    records = []
    for ref in manifest["turns"]:
        records.append({"input": read(s3, cfg["artifact_bucket"], ref["key"].replace("-output.json", "-input.json")),
                        "output": read(s3, cfg["artifact_bucket"], ref["key"])})
    history = asyncio.run(Journal(api, cfg["memory_id"], manifest["run_id"]).load(manifest["turns"]))
    verify_records(manifest, records, history)
    path = common.save("mcp-evidence", {"manifest": manifest, "records": records, "memory_history": history})
    return {"status": "completed", "run_id": manifest["run_id"], "model_id": cfg["model_id"],
            "discussion": history[:-1], "summary": history[-1]["text"],
            "memory_events": len(history), "artifact_verification": "passed", "result_file": str(path)}


@mcp.tool()
async def run_menu_meeting(input_dir: str = "briefs") -> dict:
    """Run this sample once: an AWS-hosted Group Chat about an autumn cafe menu.

    Uploads common.md, development.md, procurement.md and operations.md from input_dir.
    Relative paths resolve inside this sample. Default briefs contains fictional examples.
    Use only the user-requested directory; do not search or upload unrelated files.
    Three specialists discuss for two rounds, then a summary agent reports unresolved decisions.
    Creates a new run, S3 artifacts and seven short-term Memory events. May take several minutes.
    Returns six discussion turns, the remote summary and verified Memory evidence.
    Do not automatically retry failures. No purchasing, booking or infrastructure changes.
    """
    return await asyncio.to_thread(run_remote, input_dir)


if __name__ == "__main__":
    mcp.run(transport="http", host="127.0.0.1", port=8000, path="/mcp")
