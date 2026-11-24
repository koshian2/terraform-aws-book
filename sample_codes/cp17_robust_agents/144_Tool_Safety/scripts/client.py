"""LLMを介さず、不正な引数もHTTPで送りツール側の制約を確認する。"""

import argparse
import asyncio
import json
from datetime import datetime, timezone
from pathlib import Path

from fastmcp import Client

ROOT = Path(__file__).resolve().parents[1]
BASE = {"start_date": "2026-10-01", "end_date": "2026-10-31"}
PUBLIC_COLUMNS = {"purchase_id", "purchased_on", "product_name", "amount_yen"}


async def verify(url: str) -> Path:
    cases = [
        ("normal", {"product": "コーヒー豆"}, False, ["P012", "P004"]),
        ("bounded_result", {}, False, [f"P{i:03}" for i in range(15, 5, -1)]),
        ("limit_one", {"limit": 1}, False, ["P015"]),
        ("sql_as_text", {"product": "Reader's SELECT Blend"}, False, []),
        ("apostrophe", {"product": "Maker's"}, False, ["P013"]),
        ("too_many", {"limit": 1000}, True, None),
        ("negative_limit", {"limit": -1}, True, None),
        ("boolean_limit", {"limit": True}, True, None),
        ("string_limit", {"limit": "10"}, True, None),
        ("arbitrary_sql", {"sql": "SELECT * FROM purchases"}, True, None),
        ("private_columns", {"columns": ["email", "shipping_address", "internal_note"]}, True, None),
        ("other_table", {"table": "customers"}, True, None),
        ("invalid_date", {"start_date": "2026-02-30"}, True, None),
        ("reversed_period", {"start_date": "2026-11-01"}, True, None),
    ]
    records = []
    # コーディングエージェントと同様、initializeから始める接続で検証する。
    async with Client(url, timeout=30, mode="legacy") as client:
        tools = await client.list_tools()
        names = sorted(tool.name for tool in tools)
        if names != ["get_purchase_history"]:
            raise RuntimeError(f"想定外のツール一覧: {names}")
        print("Tools:", ", ".join(names))
        for name, overrides, expected_error, expected_ids in cases:
            arguments = BASE | overrides
            result = await client.call_tool("get_purchase_history", arguments, raise_on_error=False)
            content = [block.model_dump(mode="json") for block in result.content]
            payload = result.structured_content
            matched = result.is_error == expected_error
            if not expected_error:
                rows = (payload or {}).get("purchases", [])
                matched = matched and [row.get("purchase_id") for row in rows] == expected_ids
                matched = matched and (payload or {}).get("count") == len(expected_ids)
                matched = matched and all(set(row) == PUBLIC_COLUMNS for row in rows)
                # structuredContentだけでなく、LLMに届くtext側も確認する。
                serialized = json.dumps({"content": content, "structured": payload}, ensure_ascii=False)
                matched = matched and not any(secret in serialized for secret in
                    ("fictional@example.invalid", "PRIVATE_ADDRESS", "PRIVATE_NOTE"))
            records.append({"case": name, "arguments": arguments, "is_error": result.is_error,
                            "matched": matched, "structured_content": payload, "content": content})
            print(f"{name}: {'PASS' if matched else 'FAIL'} (is_error={result.is_error})")
    now = datetime.now(timezone.utc)
    path = ROOT / "results" / f"mcp-check-{now.strftime('%Y%m%dT%H%M%S%fZ')}.json"
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps({"checked_at": now.isoformat(), "url": url, "tools": names,
                               "all_matched": all(row["matched"] for row in records),
                               "cases": records}, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Saved: {path}")
    if not all(row["matched"] for row in records):
        raise SystemExit("想定と異なる結果があります。記録を確認してください。")
    return path


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:8000/mcp")
    asyncio.run(verify(parser.parse_args().url))
