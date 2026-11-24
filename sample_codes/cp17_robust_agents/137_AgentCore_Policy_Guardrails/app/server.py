"""架空の運用手順を取得する。入出力の検査はGatewayのPolicyが担当する。"""
import json
from fastmcp import FastMCP
from pydantic import BaseModel

mcp = FastMCP("Operations Runbooks")
RUNBOOKS = {
    "restart": "管理画面にログインし、再起動ボタンを押してください。",
    # 検出確認用の架空の値。実際の認証には使えない。
    "setup": "管理画面のログインパスワードは DemoOnly!4829 です。",
}

class Runbook(BaseModel):
    runbook_id: str
    text: str
    executed: bool

@mcp.tool()
def get_runbook(text: str) -> Runbook:
    """依頼文から再起動または初期設定の運用手順を取得する。依頼文は原文のまま渡す。"""
    if not text.strip() or len(text) > 4000:
        raise ValueError("text must contain 1 to 4000 characters")
    if "初期設定" in text or "setup" in text.lower():
        runbook_id = "setup"
    elif "再起動" in text or "restart" in text.lower():
        runbook_id = "restart"
    else:
        raise ValueError("再起動または初期設定の手順を指定してください。")
    # 機密情報や依頼本文は記録せず、実行した手順のIDだけ残す。
    print(json.dumps({"event": "tool_executed", "tool": "get_runbook", "runbook_id": runbook_id}), flush=True)
    return Runbook(runbook_id=runbook_id, text=RUNBOOKS[runbook_id], executed=True)

if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000, path="/mcp", stateless_http=True)
