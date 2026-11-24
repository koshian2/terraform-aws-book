"""商品紹介の制作をAWS上で実行するローカルHTTP MCPサーバー。"""
import asyncio
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent / "scripts"))
import common
import boto3
from botocore.config import Config
from fastmcp import FastMCP
from client import read_json
from contracts import validate_product
from pipeline import invoke_json

mcp = FastMCP("AgentCore Sequential")


def run_remote(product_file):
    path = Path(product_file)
    if not path.is_absolute():
        path = common.ROOT / path
    product = json.loads(path.read_text(encoding="utf-8"))
    validate_product(product)
    cfg = common.settings()
    session = boto3.Session(profile_name=cfg["aws_profile"], region_name=cfg["aws_region"])
    api = session.client("bedrock-agentcore", config=Config(read_timeout=720, retries={"total_max_attempts": 1}))
    result = invoke_json(api, cfg["pipeline_arn"], {"product": product})
    saved = common.save("mcp-run", result)
    manifest = result["manifest"]
    stages = []
    for entry in manifest["stages"]:
        if entry["status"] == "completed":
            stages.append(read_json(session.client("s3"), cfg["artifact_bucket"], entry["output_key"]))
    return {"manifest": manifest, "stages": stages, "result_file": str(saved)}


@mcp.tool
async def create_product_copy(product_file: str = "product.json") -> dict:
    """商品仕様から訴求整理・紹介文・SNS投稿文をAWS上で順番に作成します。

    指定されたJSONだけを読みます。相対パスはサンプル直下が基準です。
    各担当の実際の出力を順番に表示してください。処理には数分かかることがあります。
    生成結果をS3へ保存します。失敗時は自動で再実行しないでください。
    """
    return await asyncio.to_thread(run_remote, product_file)


if __name__ == "__main__":
    mcp.run(transport="http", host="127.0.0.1", port=8000, path="/mcp")
