"""削除対象を記録し、Terraform削除後に自動生成ログ・Identityを片付ける。"""
import argparse
import json
import boto3
from botocore.exceptions import ClientError
from common import ROOT, settings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["capture", "leftovers"])
    args = parser.parse_args()
    path = ROOT / "results/cleanup-inventory.json"
    cfg = settings() if args.action == "capture" else json.loads(path.read_text(encoding="utf-8"))
    session = boto3.Session(profile_name=cfg["aws_profile"], region_name=cfg["aws_region"])
    account = session.client("sts").get_caller_identity()["Account"]
    control = session.client("bedrock-agentcore-control")
    if args.action == "capture":
        runtime = control.get_agent_runtime(agentRuntimeId=cfg["runtime_id"])
        cfg["account_id"] = account
        cfg["workload_name"] = runtime["workloadIdentityDetails"]["workloadIdentityArn"].rsplit("/", 1)[1]
        evaluation = control.get_online_evaluation_config(onlineEvaluationConfigId=cfg["evaluation_id"])
        cfg["result_log"] = evaluation.get("outputConfig", {}).get("cloudWatchConfig", {}).get("logGroupName") or f"/aws/bedrock-agentcore/evaluations/results/{cfg['evaluation_id']}"
        path.parent.mkdir(exist_ok=True)
        path.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
        print(f"記録: {path}")
        return
    state = json.loads((ROOT / "terraform/terraform.tfstate").read_text(encoding="utf-8"))
    if account != cfg["account_id"] or any(r["mode"] == "managed" for r in state.get("resources", [])):
        raise RuntimeError("Account mismatch or Terraform resources remain")
    for method, key, value in [(control.get_agent_runtime, "agentRuntimeId", cfg["runtime_id"]),
                               (control.get_online_evaluation_config, "onlineEvaluationConfigId", cfg["evaluation_id"])]:
        try:
            method(**{key: value})
        except ClientError as exc:
            if exc.response["Error"]["Code"] != "ResourceNotFoundException":
                raise
        else:
            raise RuntimeError(f"Resource still exists: {value}")
    if cfg["workload_name"] != cfg["runtime_id"] or cfg["runtime_log"] != f"/aws/bedrock-agentcore/runtimes/{cfg['runtime_id']}-DEFAULT":
        raise RuntimeError("Unexpected cleanup target")
    if cfg["result_log"] != f"/aws/bedrock-agentcore/evaluations/results/{cfg['evaluation_id']}":
        raise RuntimeError("Unexpected result log group")
    logs = session.client("logs")
    for group in [cfg["runtime_log"], cfg["result_log"]]:
        try:
            logs.delete_log_group(logGroupName=group)
        except logs.exceptions.ResourceNotFoundException:
            pass
    try:
        control.delete_workload_identity(name=cfg["workload_name"])
    except ClientError as exc:
        if exc.response["Error"]["Code"] != "ResourceNotFoundException":
            raise
    print("専用ログとWorkload Identityを削除しました。共有Transaction Searchは残します。")


if __name__ == "__main__":
    main()
