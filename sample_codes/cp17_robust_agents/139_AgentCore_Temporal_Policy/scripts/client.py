"""reader/operatorの権限と、同じPolicyセッション内の操作順序を比較する。"""
import argparse
import asyncio
import base64
from datetime import datetime, timezone
import json
import sys
import uuid
from common import ROOT, settings
from connection import call, data_of
from login import login
from session import browser_logout


def username_of(token):
    # テスト対象ユーザーの取り違え防止用。認証・認可はGatewayがJWTを検証して行う。
    payload = token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))["username"]


def scenarios(is_operator):
    close = "ok" if is_operator else "policy_denied"
    # sessionのラベルが同じステップだけ同じUUIDを使う。ケース間では必ず別UUID。
    return {
        "read": [("get_inquiry", "T001", "a", "ok")],
        "close_before_read": [("close_inquiry", "T001", "a", "policy_denied")],
        "read_then_close": [("get_inquiry", "T001", "a", "ok"), ("close_inquiry", "T001", "a", close)],
        "different_ticket": [("get_inquiry", "T001", "a", "ok"), ("close_inquiry", "T002", "a", "policy_denied")],
        "different_session": [("get_inquiry", "T001", "a", "ok"), ("close_inquiry", "T001", "b", "policy_denied")],
    }


async def run(args, cfg, token):
    username = username_of(token)
    if username != cfg[args.user + "_username"]:
        raise RuntimeError(f"ログインしたユーザーは{username}です。{args.user}としてログインし直してください。")
    records = []
    folder = ROOT / "results"
    folder.mkdir(exist_ok=True)
    path = folder / ("run-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + ".json")
    try:
        for case, steps in scenarios(args.user == "operator").items():
            sessions = {label: str(uuid.uuid4()) for _, _, label, _ in steps}
            for tool, ticket, label, expected in steps:
                result = await call(cfg["mcp_url"], token, cfg["tool_prefix"] + tool,
                                    {"ticket_id": ticket}, session_id=sessions[label])
                matched = result["status"] == expected
                if matched and expected == "ok":
                    data = data_of(result)
                    matched = data.get("ticket_id") == ticket
                    if tool == "close_inquiry":
                        matched = matched and data.get("status") == "closed" and data.get("simulated") is True
                    else:
                        matched = matched and isinstance(data.get("text"), str)
                records.append({"user": username, "case": case, "tool": tool, "ticket_id": ticket,
                                "policy_session_id": sessions[label], "expected": expected,
                                "matched": matched, **result})
                print(json.dumps(records[-1], ensure_ascii=False, indent=2))
    finally:
        path.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"記録: {path}")
    if not all(record["matched"] for record in records):
        raise SystemExit("期待と異なる結果です。ユーザー・Policy・セッションIDを確認してください。")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user", choices=["reader", "operator"], required=True)
    parser.add_argument("--no-browser", action="store_true", help="ログインURLを手動で開く")
    args = parser.parse_args()
    cfg = settings()
    # 前回ログインのCookieを残したまま別ユーザーの検証を開始しない。
    browser_logout(cfg)
    print(f"Cognitoに {cfg[args.user + '_username']} でログインしてください。パスワードはユーザー作成時に設定したものです。", flush=True)
    asyncio.run(run(args, cfg, login(cfg, no_browser=args.no_browser)))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
