"""MCP response transformation using Bedrock EMAIL anonymization.

Never log the event or Guardrail assessments: both can contain original PII.
"""
import copy
import json
import os

import boto3
from botocore.config import Config

_bedrock = None


def mask_text(text):
    global _bedrock
    if _bedrock is None:
        _bedrock = boto3.client(
            "bedrock-runtime",
            config=Config(connect_timeout=3, read_timeout=15, retries={"max_attempts": 1}),
        )
    response = _bedrock.apply_guardrail(
        guardrailIdentifier=os.environ["GUARDRAIL_ID"],
        guardrailVersion=os.environ["GUARDRAIL_VERSION"],
        source="OUTPUT", content=[{"text": {"text": text}}],
    )
    if response["action"] == "NONE":
        return text
    if response["action"] == "GUARDRAIL_INTERVENED":
        outputs = response.get("outputs", [])
        if len(outputs) == 1 and isinstance(outputs[0].get("text"), str) and outputs[0]["text"]:
            return outputs[0]["text"]
    raise ValueError("Unexpected Guardrail response")


def handler(event, context):
    incoming = event["mcp"]["gatewayResponse"]
    response = {key: copy.deepcopy(incoming[key]) for key in ("statusCode", "body") if key in incoming}
    request = event["mcp"].get("gatewayRequest", {}).get("body", {})
    if request.get("method") != "tools/call":
        return {"interceptorOutputVersion": "1.0", "mcp": {"transformedGatewayResponse": response}}
    body = response.get("body", {})
    request_id = body.get("id") if isinstance(body, dict) else None
    try:
        # This Gateway has one tool and a known schema. Rebuild every successful
        # result from the masked value, removing duplicate original text/metadata.
        result = body.get("result")
        if not isinstance(result, dict) or result.get("isError"):
            raise ValueError("Tool did not return a successful result")
        data = result.get("structuredContent")
        if data is None:
            content = result.get("content", [])
            if len(content) != 1 or content[0].get("type") != "text":
                raise ValueError("Unexpected tool result schema")
            data = json.loads(content[0]["text"])
        if data.get("ticket_id") not in {"T001", "T002", "T003"} or not isinstance(data.get("text"), str):
            raise ValueError("Unexpected inquiry schema")
        masked = {"ticket_id": data["ticket_id"], "text": mask_text(data["text"])}
        body = {
            "jsonrpc": "2.0", "id": request_id,
            "result": {
                "content": [{"type": "text", "text": json.dumps(masked, ensure_ascii=False)}],
                "structuredContent": masked, "isError": False,
            },
        }
    except Exception:
        # Operational failure is not a content rejection. Never fall back to
        # returning the unprocessed inquiry if Guardrails or the tool fails.
        body = {
            "jsonrpc": "2.0", "id": request_id,
            "result": {"content": [{"type": "text", "text": "Unable to prepare inquiry response."}], "isError": True},
        }
        print("inquiry_response_processing_failed")
    response["body"] = body
    response["statusCode"] = 200
    return {"interceptorOutputVersion": "1.0", "mcp": {"transformedGatewayResponse": response}}
