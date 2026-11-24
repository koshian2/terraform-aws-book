"""Runtimeのログ保存期間を設定し、削除後に自動作成リソースを片付ける。"""
import argparse
import json
import time

import boto3
from botocore.exceptions import ClientError
from common import ROOT, settings

PATH = ROOT / "results/cleanup-inventory.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["configure", "capture", "leftovers"])
    args = parser.parse_args()
    cfg = (json.loads(PATH.read_text(encoding="utf-8"))
           if args.action == "leftovers" else settings())
    session = boto3.Session(profile_name=cfg["aws_profile"], region_name=cfg["aws_region"])
    account = session.client("sts").get_caller_identity()["Account"]
    control = session.client("bedrock-agentcore-control")
    if args.action in {"configure", "capture"}:
        runtime = control.get_agent_runtime(agentRuntimeId=cfg["runtime_id"])
        gateway = control.get_gateway(gatewayIdentifier=cfg["gateway_id"])
        identity = gateway.get("workloadIdentityDetails", {}).get("workloadIdentityArn")
        cfg["gateway_workload_name"] = identity.rsplit("/", 1)[1] if identity else None
        cfg["account_id"] = account
        cfg["workload_name"] = runtime["workloadIdentityDetails"]["workloadIdentityArn"].rsplit("/", 1)[1]
        PATH.parent.mkdir(exist_ok=True)
        PATH.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
        print(f"記録: {PATH}")
        if args.action == "configure":
            # AWSが作成するため、CreateLogGroupは呼ばず反映だけを待つ。
            logs = session.client("logs")
            deadline = time.monotonic() + 120
            while True:
                try:
                    logs.put_retention_policy(
                        logGroupName=cfg["log_group_name"], retentionInDays=7)
                    break
                except logs.exceptions.ResourceNotFoundException:
                    if time.monotonic() >= deadline:
                        raise RuntimeError(
                            "Runtimeのロググループが未作成です。"
                            "しばらく待ってcleanup.py configureを再実行してください。"
                        ) from None
                    time.sleep(5)
            print("Runtimeのログ保存期間を7日に設定しました。")
        return
    state = json.loads((ROOT / "terraform/terraform.tfstate").read_text(encoding="utf-8"))
    if account != cfg["account_id"] or any(r["mode"] == "managed" for r in state.get("resources", [])):
        raise RuntimeError("AWS account mismatch or Terraform resources remain")
    if not cfg["runtime_id"].startswith(cfg["runtime_name"] + "-") or cfg["workload_name"] != cfg["runtime_id"]:
        raise RuntimeError("Unexpected cleanup target")
    expected_log = f"/aws/bedrock-agentcore/runtimes/{cfg['runtime_id']}-DEFAULT"
    if cfg["log_group_name"] != expected_log:
        raise RuntimeError("Unexpected log group")
    try:
        control.get_agent_runtime(agentRuntimeId=cfg["runtime_id"])
    except ClientError as exc:
        if exc.response["Error"]["Code"] != "ResourceNotFoundException":
            raise
    else:
        raise RuntimeError("Runtime still exists; wait until deletion completes")
    try:
        control.get_gateway(gatewayIdentifier=cfg["gateway_id"])
    except ClientError as exc:
        if exc.response["Error"]["Code"] != "ResourceNotFoundException":
            raise
    else:
        raise RuntimeError("Gateway still exists")
    gateway_identity = cfg.get("gateway_workload_name")
    if gateway_identity and not gateway_identity.startswith(cfg["runtime_name"].replace("_", "-") + "-"):
        raise RuntimeError("Unexpected Gateway workload identity")
    if gateway_identity:
        try:
            control.delete_workload_identity(name=gateway_identity)
        except ClientError as exc:
            if exc.response["Error"]["Code"] != "ResourceNotFoundException":
                raise
    logs = session.client("logs")
    try:
        logs.delete_log_group(logGroupName=expected_log)
    except logs.exceptions.ResourceNotFoundException:
        pass
    try:
        control.delete_workload_identity(name=cfg["workload_name"])
    except ClientError as exc:
        if exc.response["Error"]["Code"] != "ResourceNotFoundException":
            raise
    print("RuntimeのログとRuntime・GatewayのWorkload Identityを削除しました（既に削除済みの場合を含む）。")


if __name__ == "__main__":
    main()
