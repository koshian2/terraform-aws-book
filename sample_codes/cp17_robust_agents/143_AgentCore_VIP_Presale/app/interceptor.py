"""商品条件を検査するREQUEST Interceptor。会員資格は後段のPolicyが判定する。"""
from datetime import datetime, timezone
import json
from pathlib import Path

PRODUCTS = json.loads(Path(__file__).with_name("products.json").read_text(encoding="utf-8"))
TOOL = "presale-runtime___reserve_product"


def check_product(arguments, now):
    if not isinstance(arguments, dict) or set(arguments) != {"product_id"}:
        return "invalid_arguments"
    product_id = arguments["product_id"]
    if not isinstance(product_id, str) or product_id not in PRODUCTS:
        return "unknown_product"
    product = PRODUCTS[product_id]
    if not product["presale"]:
        return "not_presale_product"
    starts = datetime.fromisoformat(product["starts_at"])
    ends = datetime.fromisoformat(product["ends_at"])
    if starts.tzinfo is None or ends.tzinfo is None or starts >= ends:
        raise ValueError("Invalid catalog schedule")
    if now < starts:
        return "presale_not_started"
    if now >= ends:
        return "presale_ended"
    return None


def reject(request_id, reason):
    print(json.dumps({"decision": "DENY", "reason": reason}), flush=True)
    return {
        "interceptorOutputVersion": "1.0",
        "mcp": {"transformedGatewayResponse": {
            "statusCode": 200,
            "body": {"jsonrpc": "2.0", "id": request_id, "error": {
                "code": -32048, "message": f"Presale request rejected: {reason}",
                "data": {"source": "request_interceptor", "reason": reason},
            }},
        }},
    }


def handler(event, context):
    request = event["mcp"]["gatewayRequest"]
    body = request["body"]
    # MCPの接続・一覧取得はGatewayに任せる。tools/callだけ商品検査する。
    if body.get("method") == "tools/call":
        params = body.get("params", {})
        if params.get("name") != TOOL:
            return reject(body.get("id"), "unexpected_tool")
        try:
            reason = check_product(params.get("arguments"), datetime.now(timezone.utc))
        except Exception:
            return reject(body.get("id"), "catalog_validation_failed")
        if reason:
            return reject(body.get("id"), reason)
        print(json.dumps({"decision": "PASS_TO_POLICY", "product_id": params["arguments"]["product_id"]}), flush=True)
    # gatewayRequestには入力専用のpath/httpMethodも含まれる。
    # そのまま返すとGatewayが不正なInterceptor応答として拒否する。
    return {"interceptorOutputVersion": "1.0", "mcp": {"transformedGatewayRequest": {"body": body}}}
