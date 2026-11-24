"""保存済み削除プランを適用し、Runtimeの自動生成ログも片付けます。"""
import argparse
import json
import subprocess
import boto3
from common import ROOT, settings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", required=True, help="destroy.tfplanの削除を実行")
    parser.parse_args()
    saved = ROOT / "build/cleanup.json"
    if not saved.exists():
        config = settings()
        saved.parent.mkdir(exist_ok=True)
        saved.write_text(json.dumps({key: config[key] for key in ("aws_profile", "aws_region", "log_group_name")}), encoding="utf-8")
    config = json.loads(saved.read_text(encoding="utf-8"))
    # 削除後にログ削除が失敗しても、次回は同じ対象で再試行できる。
    state = subprocess.run(["terraform", f"-chdir={ROOT / 'terraform'}", "state", "list"], check=True, capture_output=True, text=True)
    if state.stdout.strip():
        if settings()["log_group_name"] != config["log_group_name"]:
            raise SystemExit("保存済みのログ削除対象と現在のRuntimeが異なります。build/cleanup.jsonを確認してください。")
        result = subprocess.run(
            ["terraform", f"-chdir={ROOT / 'terraform'}", "show", "-json", "destroy.tfplan"],
            check=True, capture_output=True, text=True, encoding="utf-8",
        )
        changes = json.loads(result.stdout).get("resource_changes", [])
        managed = [item for item in changes if item.get("mode") == "managed"]
        current = {line for line in state.stdout.splitlines() if line and not line.startswith("data.")}
        if not managed or {item["address"] for item in managed} != current or any(item["change"]["actions"] != ["delete"] for item in managed):
            raise SystemExit("削除専用のplanではありません。plan -destroyをやり直してください。")
        subprocess.run(["terraform", f"-chdir={ROOT / 'terraform'}", "apply", "destroy.tfplan"], check=True)
        remaining = subprocess.run(["terraform", f"-chdir={ROOT / 'terraform'}", "state", "list"], check=True, capture_output=True, text=True)
        if remaining.stdout.strip():
            raise SystemExit("ステートにリソースが残っています。ログは削除せず停止します。")
    logs = boto3.Session(profile_name=config["aws_profile"], region_name=config["aws_region"]).client("logs")
    try:
        logs.delete_log_group(logGroupName=config["log_group_name"])
    except logs.exceptions.ResourceNotFoundException:
        pass
    saved.unlink()
    print("Terraform管理リソースとRuntimeログを削除しました。")


if __name__ == "__main__":
    main()
