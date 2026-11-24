"""ConverseのGuardrail適用と、指定省略時のIAM拒否を比較する。"""
import os

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError


def lambda_handler(event, context):
    prompt = event.get("prompt")
    mode = event.get("mode", "guarded")
    if not isinstance(prompt, str) or not prompt.strip() or len(prompt) > 4000:
        raise ValueError("prompt must contain 1 to 4000 characters")
    if mode not in {"guarded", "unguarded"}:
        raise ValueError("mode must be guarded or unguarded")

    request = {
        "modelId": os.environ["MODEL_ID"],
        "system": [{"text": "あなたは架空の家電メーカーの商品案内担当です。家電選びの一般的な質問に日本語で簡潔に答えてください。存在しない商品仕様を作らないでください。"}],
        "messages": [{"role": "user", "content": [{"text": prompt}]}],
        "inferenceConfig": {"maxTokens": 512},
    }
    if mode == "guarded":
        request["guardrailConfig"] = {
            "guardrailIdentifier": os.environ["GUARDRAIL_ID"],
            "guardrailVersion": os.environ["GUARDRAIL_VERSION"],
            "trace": "enabled",
        }
    # unguardedでも実際にBedrockへ送信する。コード内で拒否を模擬しない。
    client = boto3.client("bedrock-runtime", config=Config(
        connect_timeout=5, read_timeout=100, retries={"total_max_attempts": 1}
    ))
    try:
        result = client.converse(**request)
    except ClientError as exc:
        if exc.response["Error"]["Code"] != "AccessDeniedException":
            raise
        return {
            "status": "access_denied", "mode": mode,
            "error": exc.response["Error"],
            "request_id": exc.response.get("ResponseMetadata", {}).get("RequestId"),
        }

    return {
        "status": "blocked" if result["stopReason"] == "guardrail_intervened" else "answered",
        "mode": mode,
        "stop_reason": result["stopReason"],
        "text": "\n".join(c["text"] for c in result["output"]["message"]["content"] if "text" in c),
        "guardrail_trace": result.get("trace", {}).get("guardrail", {}),
        "usage": result.get("usage", {}),
    }
