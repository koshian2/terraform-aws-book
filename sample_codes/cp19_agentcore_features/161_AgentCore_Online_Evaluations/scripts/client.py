"""普通の相談を送るだけ。評価APIは呼ばず、オンライン評価の到着を別途確認する。"""
import argparse
from datetime import datetime, timezone
import json
import uuid

import boto3
from botocore.config import Config
from common import ROOT, settings

CASES = {
    "change_quantity": [
        "ノート(P001)とペン(P002)を1つずつ買いたいです。予算は500円です。合計金額と予算内かを教えてください。",
        "ではペンを2本に変更してください。他の条件はそのままで、内訳と合計、予算内かを教えてください。",
    ],
    "unknown_product": ["未登録の商品P999とノートP001を1つずつ、予算500円で見積もってください。"],
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", choices=["both", "forgetful", "fixed"], default="both")
    args = parser.parse_args()
    cfg = settings()
    session = boto3.Session(profile_name=cfg["aws_profile"], region_name=cfg["aws_region"])
    control = session.client("bedrock-agentcore-control")
    evaluation = control.get_online_evaluation_config(onlineEvaluationConfigId=cfg["evaluation_id"])
    if evaluation["status"] != "ACTIVE" or evaluation["executionStatus"] != "ENABLED":
        raise RuntimeError("Online evaluation must be ACTIVE and ENABLED before sending traffic")
    api = session.client("bedrock-agentcore", config=Config(read_timeout=300, retries={"total_max_attempts": 1}))
    started = datetime.now(timezone.utc)
    record = {"started_at": started.isoformat(), "config": cfg, "sessions": [], "status": "running"}
    ROOT.joinpath("results").mkdir(exist_ok=True)
    path = ROOT / "results" / f"calls-{started.strftime('%Y%m%dT%H%M%SZ')}.json"
    variants = ["forgetful", "fixed"] if args.variant == "both" else [args.variant]
    try:
        for variant in variants:
            for case, prompts in CASES.items():
                sid = str(uuid.uuid4())
                item = {"session_id": sid, "variant": variant, "case": case, "turns": []}
                record["sessions"].append(item)
                for prompt in prompts:
                    response = api.invoke_agent_runtime(agentRuntimeArn=cfg["runtime_arn"], runtimeSessionId=sid,
                        contentType="application/json", accept="application/json",
                        payload=json.dumps({"prompt": prompt, "variant": variant}).encode())
                    body = response["response"].read().decode()
                    answer = json.loads(body)
                    item["turns"].append({"prompt": prompt, "response": answer,
                                           "http_status": response["ResponseMetadata"]["HTTPStatusCode"]})
                    print(f"[{variant}/{case}] {answer}", flush=True)
        record["status"] = "completed"
    finally:
        text = json.dumps(record, ensure_ascii=False, indent=2) + "\n"
        path.write_text(text, encoding="utf-8")
        (ROOT / "results/latest-calls.json").write_text(text, encoding="utf-8")
        print(f"記録: {path}")


if __name__ == "__main__":
    main()
