"""ログインした会社の取得結果と、テナント情報の改変を試した結果を記録する。"""
import argparse
import asyncio
import base64
from datetime import datetime, timezone
import json

import httpx2 as httpx
from common import ROOT, settings
from login import login
from session import browser_logout
from transport import GatewayClient

EXPECTED = {"tenant-a": "商品が届きません。", "tenant-b": "請求書の宛名を変更してください。"}
HEADER = "X-Amzn-Bedrock-AgentCore-Runtime-Custom-Tenant-Id"


def check_identity(token, username, tenant):
    # ログイン先の取り違えを検出するだけ。署名の検証はGatewayが行う。
    part = token.split(".")[1]
    claims = json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))
    if (claims.get("username"), claims.get("tenant_id"), claims.get("token_use")) != (username, tenant, "access"):
        raise RuntimeError("指定したユーザー・テナントでログインしていません。")


def value(result):
    if result.get("isError"):
        raise RuntimeError("Runtime returned a tool error")
    return result.get("structuredContent") or json.loads(result["content"][0]["text"])


async def run(args):
    cfg = settings()
    browser_logout(cfg)
    print(f"Cognitoに {args.username}（{args.tenant}）でログインしてください。", flush=True)
    token = login(cfg)
    check_identity(token, args.username, args.tenant)
    records = []
    path = ROOT / "results" / (args.tenant + "-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + ".json")
    other = "tenant-b" if args.tenant == "tenant-a" else "tenant-a"

    def record(case, actual, expected):
        item = {"case": case, "tenant": args.tenant, "actual": actual,
                "expected": expected, "matched": actual == expected}
        records.append(item)
        print(json.dumps(item, ensure_ascii=False), flush=True)
        if not item["matched"]:
            raise RuntimeError("期待と異なる結果です。ログインした所属と設定を確認してください。")

    try:
        # 上書きされたテナントヘッダーで、他社へ切り替わらないことを確認する。
        for forged in (False, True):
            headers = {"Authorization": "Bearer " + token}
            if forged:
                headers[HEADER] = other
            async with httpx.AsyncClient(headers=headers, timeout=120) as http:
                mcp = GatewayClient(http, cfg["mcp_url"])
                await mcp.initialize()
                listed = (await mcp.list_tools())["tools"]
                tools = {t["name"]: t for t in listed}
                name = cfg["tool_prefix"] + "get_inquiry"
                expected_names = [name]
                if cfg["isolation_mode"] == "leading_keys":
                    expected_names.append(cfg["tool_prefix"] + "verify_tenant_isolation")
                record("tools" + ("_forged_header" if forged else ""), sorted(tools), sorted(expected_names))
                record("arguments" + ("_forged_header" if forged else ""),
                       sorted(tools[name]["inputSchema"]["properties"]), ["ticket_id"])
                result = value(await mcp.call_tool(name, {"ticket_id": "T001"}))
                record("forged_header" if forged else "own_inquiry", result,
                       {"ticket_id": "T001", "found": True, "text": EXPECTED[args.tenant]})
                if not forged:
                    record("missing_inquiry", value(await mcp.call_tool(name, {"ticket_id": "T999"})),
                           {"ticket_id": "T999", "found": False})
                    extra = await mcp.call_tool(name, {"ticket_id": "T001", "tenant_id": other})
                    record("tenant_argument_rejected", bool(extra.get("isError")), True)
                    if cfg["isolation_mode"] == "leading_keys":
                        result = value(await mcp.call_tool(cfg["tool_prefix"] + "verify_tenant_isolation", {}))
                        record("iam_isolation", result, {"status": "pass", "own_partition_readable": True,
                            "other_partitions_denied": True, "scan_denied": True,
                            "missing_tag_denied": True, "unknown_tag_denied": True})
    finally:
        path.parent.mkdir(exist_ok=True)
        path.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"記録: {path}", flush=True)
    print("PASS: all expected results matched", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--username", required=True)
    parser.add_argument("--tenant", choices=["tenant-a", "tenant-b"], required=True)
    args = parser.parse_args()
    try:
        asyncio.run(run(args))
    except Exception as error:
        print(str(error) if type(error) is RuntimeError else "Failure type: " + type(error).__name__)
        raise SystemExit(1) from None
