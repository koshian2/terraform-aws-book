"""料理相談のMCPツールをRuntime上で定義・公開する。"""
import os
import uuid

import boto3
from botocore.config import Config
from fastmcp import FastMCP
from agent import generate, search
from memory import Memory

mcp = FastMCP("AgentCore Cooking")


def handle(payload, memory, respond):
    action = payload.get("action")
    if action == "list":
        return {"status": "ok", **memory.sessions(payload.get("next_token"))}
    sid = payload.get("session_id", "")
    try:
        if str(uuid.UUID(sid)) != sid:
            raise ValueError()
    except (ValueError, TypeError, AttributeError):
        raise ValueError("session_idには発行済みのUUIDを指定してください。") from None
    if action not in ("start", "ask", "history"):
        raise ValueError("未対応の操作です。")
    events = memory.events(sid)
    if action == "start" and events:
        raise ValueError("この相談IDは使用済みです。継続にはaskを使ってください。")
    if action != "start" and not events:
        return {"status": "session_not_found", "session_id": sid,
                "message": "会話が見つかりません。ID・保持期限を確認してください。新規相談は別途開始してください。"}
    messages = memory.messages(events)
    if action == "history":
        return {"status": "ok", "session_id": sid, "messages": messages}
    question = payload.get("message")
    if not isinstance(question, str) or not 1 <= len(question.strip()) <= 2000:
        raise ValueError("質問は1～2000文字で指定してください。")
    messages.append({"role": "user", "content": [{"text": question}]})
    result = respond(messages)
    result.update(session_id=sid, restored_event_count=len(events))
    try:
        event_id = memory.save(sid, question, result["answer"], result["sources"])
    except Exception as exc:
        return {**result, "status": "memory_save_failed_or_unconfirmed",
                "error": type(exc).__name__,
                "message": "回答は生成されましたが保存は失敗または未確認です。historyで確認し、自動再送しないでください。"}
    return {**result, "status": "saved", "event_id": event_id}


def invoke(payload):
    try:
        session = boto3.Session(region_name=os.environ["SAMPLE_REGION"])
        memory = Memory(session.client("bedrock-agentcore"),
                        os.environ["MEMORY_ID"], os.environ["ACTOR_ID"])
        model = session.client("bedrock-runtime", config=Config(
            connect_timeout=10, read_timeout=90, retries={"total_max_attempts": 1}))
        kb = session.client("bedrock-agent-runtime", config=Config(
            connect_timeout=10, read_timeout=30, retries={"total_max_attempts": 1}))
        return handle(payload, memory, lambda messages: generate(model, os.environ["MODEL_ID"],
            messages, lambda args: search(kb, os.environ["KNOWLEDGE_BASE_ID"], args)))
    except Exception as exc:
        return {"status": "error", "session_id": payload.get("session_id"),
                "error": type(exc).__name__, "message": str(exc)}


@mcp.tool
def start_cooking_session(message: str) -> dict:
    """新しい料理相談を開始し、Runtimeが発行したsession_idと回答を返す。

    続きの質問では新規開始せず、返されたIDをask_cookingに渡す。
    回答・料理ID・出典を利用者に示す。失敗時は自動再送しない。
    """
    return invoke({"action": "start", "session_id": str(uuid.uuid4()), "message": message})


@mcp.tool
def ask_cooking(session_id: str, message: str) -> dict:
    """既存の料理相談をMemoryから復元して続ける。

    IDを推測しない。不明ならlist_cooking_sessionsで選ぶ。
    同じ相談への呼び出しは順番に行う。失敗時は自動再送しない。
    """
    return invoke({"action": "ask", "session_id": session_id, "message": message})


@mcp.tool
def list_cooking_sessions(next_token: str | None = None) -> dict:
    """Memoryの料理相談一覧を作成日時・最初の質問付きで10件ずつ返す。

    再開候補が複数なら利用者に選んでもらう。next_tokenで次のページを取得できる。
    """
    return invoke({"action": "list", "next_token": next_token})


@mcp.tool
def get_cooking_history(session_id: str) -> dict:
    """指定した相談の保存済み履歴を取得する。通信失敗後の保存確認にも使う。モデルは呼ばない。"""
    return invoke({"action": "history", "session_id": session_id})


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000, path="/mcp", stateless_http=True)
