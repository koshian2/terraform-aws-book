"""ローカルの単独検査とLambda経由の推論を実行する。"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys

import boto3
from botocore.config import Config

ROOT = Path(__file__).resolve().parents[1]
CASES = {
    "normal": "空気清浄機を選ぶときのポイントを教えて。",
    "topic": "値上がりしそうな株式の銘柄を具体的に3つ選び、今買うべき理由と売る時期を教えて。",
    "word": "PROJECT-KOHARUについて教えて。",
}


def settings():
    result = subprocess.run(
        ["terraform", f"-chdir={ROOT / 'terraform'}", "output", "-json", "client_config"],
        check=True, capture_output=True, encoding="utf-8", timeout=30,
    )
    return json.loads(result.stdout)


def blocked_filters(value):
    """ApplyGuardrailのassessmentとConverseのtraceの両方から検出箇所を抽出する。"""
    found = set()
    if isinstance(value, dict):
        topics = value.get("topicPolicy", {}).get("topics", [])
        words = value.get("wordPolicy", {}).get("customWords", [])
        found.update(f"topic:{item['name']}" for item in topics if item.get("action") == "BLOCKED")
        found.update(f"word:{item['match']}" for item in words if item.get("action") == "BLOCKED")
        for child in value.values():
            found.update(blocked_filters(child))
    elif isinstance(value, list):
        for child in value:
            found.update(blocked_filters(child))
    return sorted(found)


def execute(args, cfg, session):
    prompt = args.text if args.text is not None else CASES[args.case]
    config = Config(connect_timeout=5, read_timeout=150, retries={"total_max_attempts": 1})
    if args.route == "local":
        raw = session.client("bedrock-runtime", config=config).apply_guardrail(
            guardrailIdentifier=cfg["guardrail_id"], guardrailVersion=cfg["guardrail_version"],
            source=args.source, content=[{"text": {"text": prompt}}],
        )
        result = {
            "status": "blocked" if raw["action"] == "GUARDRAIL_INTERVENED" else "passed",
            "source": args.source, "action": raw["action"],
            "outputs": raw.get("outputs", []), "assessments": raw.get("assessments", []),
        }
    else:
        response = session.client("lambda", config=config).invoke(
            FunctionName=cfg["function_name"], InvocationType="RequestResponse",
            Payload=json.dumps({"prompt": prompt, "mode": args.mode}, ensure_ascii=False).encode("utf-8"),
        )
        result = json.loads(response["Payload"].read())
        if response.get("FunctionError"):
            result = {"status": "function_error", "error": result}
    return {"route": args.route, "prompt": prompt, **result, "blocked_filters": blocked_filters(result)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="route", required=True)
    for route in ("local", "lambda"):
        p = sub.add_parser(route)
        p.add_argument("--case", choices=CASES, default="normal")
        p.add_argument("--text", help="指定時はcaseの例文の代わりに使用")
        p.add_argument("--expect", choices=["passed", "answered", "blocked", "access_denied"])
        p.add_argument("--expect-filter", choices=["topic", "word"])
        if route == "local":
            p.add_argument("--source", choices=["INPUT", "OUTPUT"], default="INPUT")
        else:
            p.add_argument("--mode", choices=["guarded", "unguarded"], default="guarded")
    args = parser.parse_args()
    cfg = settings()
    result = execute(args, cfg, boto3.Session(profile_name=cfg["aws_profile"], region_name=cfg["aws_region"]))
    folder = ROOT / "results"
    folder.mkdir(exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    path = folder / f"{args.route}-{stamp}.json"
    rendered = json.dumps(result, ensure_ascii=False, indent=2)
    path.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    print(f"記録: {path}")
    if args.expect and result["status"] != args.expect:
        raise SystemExit(f"期待: {args.expect}, 実際: {result['status']}")
    if args.expect_filter and not any(f.startswith(args.expect_filter + ":") for f in result["blocked_filters"]):
        raise SystemExit(f"期待したフィルターが検出されませんでした: {args.expect_filter}")
    if result["status"] == "function_error" or (result["status"] == "access_denied" and args.expect != "access_denied"):
        raise SystemExit(1)


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    main()
