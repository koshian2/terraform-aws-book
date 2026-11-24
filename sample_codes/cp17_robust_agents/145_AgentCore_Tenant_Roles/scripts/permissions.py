"""IAMシミュレーターで、各readerとRuntimeの読み取り権限を確認する。"""
import argparse
from datetime import datetime, timezone
import json
import subprocess

import boto3
from common import ROOT, settings


def output(name):
    result = subprocess.run(["terraform", f"-chdir={ROOT / 'terraform'}", "output", "-json", name],
                            capture_output=True, text=True, encoding="utf-8", check=True)
    return json.loads(result.stdout)


def simulate_reads(iam, role_arn, resources):
    """Read per-resource decisions, not the aggregate decision for an action."""
    decisions = {}
    pages = iam.get_paginator("simulate_principal_policy").paginate(
        PolicySourceArn=role_arn, ActionNames=["dynamodb:GetItem"], ResourceArns=resources)
    for page in pages:
        for result in page["EvaluationResults"]:
            if result["EvalActionName"] != "dynamodb:GetItem":
                raise RuntimeError("Unexpected simulator action")
            for resource in result.get("ResourceSpecificResults", []):
                arn = resource["EvalResourceName"]
                decision = resource["EvalResourceDecision"]
                if resource.get("MissingContextValues"):
                    raise RuntimeError(f"Missing simulator context for {arn}")
                if decision not in ("allowed", "implicitDeny", "explicitDeny"):
                    raise RuntimeError(f"Unexpected simulator decision: {decision}")
                if arn in decisions and decisions[arn] != decision:
                    raise RuntimeError(f"Conflicting simulator decisions for {arn}")
                decisions[arn] = decision
    if set(decisions) != set(resources):
        raise RuntimeError(f"Incomplete simulator resource results: expected {len(resources)}, got {len(decisions)}")
    return decisions


def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    cfg = settings()
    session = boto3.Session(profile_name=cfg["aws_profile"], region_name=cfg["aws_region"])
    iam = session.client("iam")
    tenants = output("tenant_config")
    runtime = output("runtime_role_arn")
    partition, account = runtime.split(":")[1], runtime.split(":")[4]
    tables = {tenant: f"arn:{partition}:dynamodb:{cfg['aws_region']}:{account}:table/{target['table_name']}"
              for tenant, target in tenants.items()}
    records = []
    for owner, arn in [(t, v["role_arn"]) for t, v in tenants.items()] + [("runtime", runtime)]:
        decisions = simulate_reads(iam, arn, list(tables.values()))
        for target, resource in tables.items():
            decision = decisions[resource]
            allowed = decision == "allowed"
            records.append({"check_type": "iam_simulator", "role": owner, "table": target,
                            "decision": decision, "matched": allowed == (owner == target)})
    path = ROOT / "results" / ("permissions-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + ".json")
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(records, ensure_ascii=False, indent=2))
    print(f"記録: {path}")
    if not all(row["matched"] for row in records):
        raise RuntimeError("IAMの許可範囲が期待と異なります。")
    print("PASS: IAM simulator（実際のDynamoDBへの越境アクセス試行ではありません）")


if __name__ == "__main__":
    main()
