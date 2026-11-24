"""Runtimeが渡すログの保存先を使い、会話付きスパンを専用ログへ送る。"""
import os

# Runtimeのログ用ヘッダーからグループ名だけを取得する。
# TerraformのRuntime定義から自身のIDを参照する循環依存を避ける。
headers = dict(part.split("=", 1) for part in os.environ.get("OTEL_EXPORTER_OTLP_LOGS_HEADERS", "").split(",") if "=" in part)
group = headers.get("x-aws-log-group")
if not group:
    raise RuntimeError("AgentCore Runtime did not supply its log group")
os.environ["OTEL_EXPORTER_OTLP_TRACES_HEADERS"] = f"x-aws-log-group={group},x-aws-log-stream=spans"

from opentelemetry.instrumentation.auto_instrumentation import initialize

initialize(swallow_exceptions=False)

from server import main

main()
