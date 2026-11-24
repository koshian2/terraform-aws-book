"""KBの取り込みと、Runtime経由の料理相談。"""
import argparse
import json
import sys
import time
import asyncio
from connection import connect, remote_transport
import common


def sync(config, timeout):
    api = common.aws_session(config).client("bedrock-agent")
    ids = {"knowledgeBaseId": config["knowledge_base_id"], "dataSourceId": config["data_source_id"]}
    job = api.start_ingestion_job(**ids, description="Cooking recipe synchronization")["ingestionJob"]
    print("Ingestion job:", job["ingestionJobId"], flush=True)
    deadline = time.monotonic() + timeout
    while True:
        job = api.get_ingestion_job(**ids, ingestionJobId=job["ingestionJobId"])["ingestionJob"]
        print(job["status"], job.get("statistics", {}), flush=True)
        if job["status"] in ("COMPLETE", "FAILED", "STOPPED"):
            print("Saved:", common.save("sync", job))
            if job["status"] != "COMPLETE" or job.get("statistics", {}).get("numberOfDocumentsFailed", 0):
                raise RuntimeError("取り込みに失敗しました。保存した記録を確認してください。")
            return
        if time.monotonic() >= deadline:
            common.save("sync-timeout", job)
            raise TimeoutError("取り込み待機を終了しました。AWS側のジョブは継続している可能性があります。")
        time.sleep(5)


async def call(action, message=None, session_id=None, next_token=None, url=None):
    names = {"start": "start_cooking_session", "ask": "ask_cooking",
             "list": "list_cooking_sessions", "history": "get_cooking_history"}
    arguments = {}
    if action in ("start", "ask"):
        arguments["message"] = message
    if action in ("ask", "history"):
        arguments["session_id"] = session_id
    if action == "list" and next_token:
        arguments["next_token"] = next_token
    request_path = common.save("request", {"tool": names[action], "arguments": arguments})
    try:
        async with connect(url if url else remote_transport()) as client:
            response = await client.call_tool(names[action], arguments)
            if response.is_error:
                raise RuntimeError(str(response.content))
            result = response.structured_content
            if result is None:
                result = json.loads(next(item.text for item in response.content if item.type == "text"))
    except Exception as exc:
        result = {"status": "invocation_failed_or_unconfirmed", "session_id": session_id,
                  "error": type(exc).__name__, "message": str(exc),
                  "request_file": str(request_path),
                  "next_action": "自動再送せずlistまたはhistoryで保存状態を確認してください。新規開始のIDは応答がないと不明です。"}
    result["result_file"] = str(common.save("response", result))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", help="HTTP MCPの接続先。省略時はRuntimeへIAM署名付きで接続")
    sub = parser.add_subparsers(dest="action", required=True)
    ingest = sub.add_parser("sync")
    ingest.add_argument("--timeout", type=int, default=900)
    start = sub.add_parser("start")
    start.add_argument("message")
    ask = sub.add_parser("ask")
    ask.add_argument("session_id")
    ask.add_argument("message")
    history = sub.add_parser("history")
    history.add_argument("session_id")
    listing = sub.add_parser("list")
    listing.add_argument("--next-token")
    args = parser.parse_args()
    if args.action == "sync":
        if args.timeout <= 0:
            parser.error("--timeout must be positive")
        sync(common.settings(), args.timeout)
        return 0
    result = asyncio.run(call(args.action, getattr(args, "message", None),
                  getattr(args, "session_id", None), getattr(args, "next_token", None), args.url))
    print(json.dumps(result, ensure_ascii=False, indent=2, default=str))
    return 0 if result["status"] in ("ok", "saved") else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {type(exc).__name__}: {exc}", file=sys.stderr)
        raise SystemExit(1)
