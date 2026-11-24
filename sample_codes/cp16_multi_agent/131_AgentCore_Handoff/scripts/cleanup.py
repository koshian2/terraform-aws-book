"""Capture automatically generated identities/logs; remove after Terraform destroy."""
import common
import argparse
import json

import boto3
from botocore.exceptions import ClientError

PATH = common.ROOT / "results/cleanup-inventory.json"


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("action", choices=["capture", "leftovers"])
    action = p.parse_args().action
    cfg = common.settings() if action == "capture" else json.loads(PATH.read_text(encoding="utf-8"))
    session = boto3.Session(profile_name=cfg["aws_profile"], region_name=cfg["aws_region"])
    cp = session.client("bedrock-agentcore-control")
    account = session.client("sts").get_caller_identity()["Account"]
    if action == "capture":
        cfg["account_id"] = account
        cfg["workload_names"] = [cp.get_agent_runtime(agentRuntimeId=rid)["workloadIdentityDetails"]["workloadIdentityArn"].rsplit("/", 1)[1]
                                 for rid in cfg["runtime_ids"].values()]
        PATH.parent.mkdir(exist_ok=True)
        PATH.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
        print("Captured:", PATH)
        return
    state = json.loads((common.ROOT / "terraform/terraform.tfstate").read_text(encoding="utf-8"))
    if account != cfg["account_id"] or any(r["mode"] == "managed" for r in state.get("resources", [])):
        raise RuntimeError("Wrong account or Terraform-managed resources remain")
    for rid in cfg["runtime_ids"].values():
        if not rid.startswith("handoff_"):
            raise RuntimeError("Unexpected Runtime ID")
        try:
            cp.get_agent_runtime(agentRuntimeId=rid)
        except ClientError as exc:
            if exc.response["Error"]["Code"] != "ResourceNotFoundException":
                raise
        else:
            raise RuntimeError("Runtime still exists")
    for rid in cfg["runtime_ids"].values():
        name = f"/aws/bedrock-agentcore/runtimes/{rid}-DEFAULT"
        try:
            session.client("logs").delete_log_group(logGroupName=name)
        except ClientError as exc:
            if exc.response["Error"]["Code"] != "ResourceNotFoundException":
                raise
        print("Removed or already absent:", name)
    for name in cfg["workload_names"]:
        if not name.startswith("handoff_"):
            raise RuntimeError("Unexpected identity name")
        try:
            cp.delete_workload_identity(name=name)
        except ClientError as exc:
            if exc.response["Error"]["Code"] != "ResourceNotFoundException":
                raise
        print("Removed or already absent:", name)


if __name__ == "__main__":
    main()
