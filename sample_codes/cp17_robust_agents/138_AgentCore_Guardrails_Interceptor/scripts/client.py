"""1回ログインし、メールを含む問い合わせと通常の問い合わせを比較する。"""
import argparse
import asyncio
from datetime import datetime, timezone
import json
import sys

from common import ROOT, settings
from connection import call, data_of
from login import login

EXPECTED = {
    "T001": "商品が届きません。連絡先は {EMAIL} です。",
    "T002": "商品の交換を希望します。連絡先は {EMAIL} です。",
    "T003": "領収書の発行方法を教えてください。",
}


async def run(args, config, token):
    tickets = list(EXPECTED) if args.ticket == "all" else [args.ticket]
    records = []
    for ticket in tickets:
        result = await call(config["mcp_url"], token, "inquiry-runtime___get_inquiry", {"ticket_id": ticket})
        matched = result["status"] == "ok"
        if matched:
            data = data_of(result)
            content = result["result"].get("content", [])
            matched = data == {"ticket_id": ticket, "text": EXPECTED[ticket]}
            matched = matched and len(content) == 1 and content[0].get("type") == "text"
            if matched:
                matched = json.loads(content[0]["text"]) == data
            # 両表現と追加フィールドも含め、元メールが応答に残っていないか確認する。
            matched = matched and "@example.com" not in json.dumps(result, ensure_ascii=False)
        records.append({"ticket_id": ticket, "matched": matched, **result})
    folder = ROOT / "results"
    folder.mkdir(exist_ok=True)
    path = folder / ("run-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + ".json")
    text = json.dumps(records, ensure_ascii=False, indent=2)
    path.write_text(text + "\n", encoding="utf-8")
    print(text)
    print(f"記録: {path}")
    if not all(r["matched"] for r in records):
        raise SystemExit("期待と異なる結果です。InterceptorとGuardrailを確認してください。")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ticket", choices=["all", *EXPECTED], default="all")
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args()
    cfg = settings()
    asyncio.run(run(args, cfg, login(cfg, no_browser=args.no_browser)))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
