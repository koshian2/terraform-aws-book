"""保存済みのセッションに対するオンライン評価を待つ。エージェントは呼び直さない。"""
import argparse
from collections import Counter
from datetime import datetime, timezone
import json
import time

import boto3
from common import ROOT


def events(logs, group, start):
    result = []
    try:
        for page in logs.get_paginator("filter_log_events").paginate(logGroupName=group, startTime=start):
            for item in page.get("events", []):
                try:
                    result.append(json.loads(item["message"]))
                except json.JSONDecodeError:
                    continue
    except logs.exceptions.ResourceNotFoundException:
        pass
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--calls", type=str, default="results/latest-calls.json")
    parser.add_argument("--wait-seconds", type=int, default=900)
    args = parser.parse_args()
    calls = json.loads((ROOT / args.calls).read_text(encoding="utf-8"))
    if calls["status"] != "completed":
        raise RuntimeError("The calls file is incomplete; inspect the responses first")
    cfg = calls["config"]
    session = boto3.Session(profile_name=cfg["aws_profile"], region_name=cfg["aws_region"])
    logs = session.client("logs")
    control = session.client("bedrock-agentcore-control")
    evaluation = control.get_online_evaluation_config(onlineEvaluationConfigId=cfg["evaluation_id"])
    output = evaluation.get("outputConfig", {}).get("cloudWatchConfig", {})
    group = output.get("logGroupName") or f"/aws/bedrock-agentcore/evaluations/results/{cfg['evaluation_id']}"
    start = int(datetime.fromisoformat(calls["started_at"]).timestamp() * 1000) - 1000
    deadline = time.monotonic() + args.wait_seconds
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    while True:
        raw = events(logs, group, start)
        summaries = []
        complete = True
        for item in calls["sessions"]:
            selected = [row for row in raw
                        if row.get("attributes", {}).get("session.id") == item["session_id"]
                        and row.get("onlineEvaluationConfigId") == cfg["evaluation_id"]]
            # 同じ対象の再配信や再評価があっても、別ターンの評価が届いたとは数えない。
            latest = {}
            for row in sorted(selected, key=lambda r: r.get("observedTimeUnixNano", 0)):
                attrs = row.get("attributes", {})
                latest[(attrs.get("gen_ai.evaluation.name"), attrs.get("gen_ai.response.id"))] = row
            counts = Counter()
            scores = []
            for row in latest.values():
                attrs = row.get("attributes", {})
                name = attrs.get("gen_ai.evaluation.name", "")
                value = attrs.get("gen_ai.evaluation.score.value")
                label = attrs.get("gen_ai.evaluation.score.label")
                if name and (value is not None or label is not None):
                    counts[name.removeprefix("Builtin.")] += 1
                    scores.append({"evaluator": name, "value": value, "label": label,
                                   "explanation": attrs.get("gen_ai.evaluation.explanation"),
                                   "trace_id": row.get("traceId")})
            ok = counts["Helpfulness"] >= len(item["turns"]) and counts["GoalSuccessRate"] >= 1
            complete = complete and ok
            summaries.append({"session_id": item["session_id"], "variant": item["variant"],
                              "case": item["case"], "complete": ok, "counts": dict(counts), "scores": scores})
        result = {"status": "observed" if complete else "pending", "source_calls": args.calls,
                  "checked_at": datetime.now(timezone.utc).isoformat(),
                  "result_log_group": group, "sessions": summaries, "raw_events": raw}
        text = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
        (ROOT / "results/latest-evaluations.json").write_text(text, encoding="utf-8")
        (ROOT / f"results/evaluations-{stamp}.json").write_text(text, encoding="utf-8")
        print(json.dumps({"status": result["status"], "counts": [x["counts"] for x in summaries]}, ensure_ascii=False), flush=True)
        if complete:
            for item in summaries:
                print(json.dumps(item, ensure_ascii=False), flush=True)
            print("PASS: every session has online evaluation scores (score improvement is not asserted)")
            return
        if time.monotonic() >= deadline:
            raise SystemExit("評価は未到着または不足です。latest-evaluations.jsonを確認し、observeだけを再実行してください。")
        time.sleep(min(20, max(0, deadline - time.monotonic())))


if __name__ == "__main__":
    main()
