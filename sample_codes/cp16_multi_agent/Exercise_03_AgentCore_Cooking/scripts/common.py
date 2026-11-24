"""Terraform設定とローカルの実行記録。"""
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess

import boto3

ROOT = Path(__file__).resolve().parents[1]


def settings():
    result = subprocess.run(["terraform", f"-chdir={ROOT / 'terraform'}", "output", "-json", "client_config"],
        capture_output=True, encoding="utf-8", check=True, timeout=30)
    return json.loads(result.stdout)


def aws_session(config):
    return boto3.Session(profile_name=config["aws_profile"], region_name=config["aws_region"])


def save(label, value):
    folder = ROOT / "results"
    folder.mkdir(exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    path = folder / f"{label}-{stamp}.json"
    path.write_text(json.dumps(value, ensure_ascii=False, default=str, indent=2) + "\n", encoding="utf-8")
    return path
