"""Local AWS / Terraform helpers. No credentials are stored in this project."""
import json
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def settings():
    result = subprocess.run(
        ["terraform", "output", "-json", "client_config"],
        cwd=ROOT / "terraform", stdin=subprocess.DEVNULL, capture_output=True, encoding="utf-8", check=True, timeout=30)
    return json.loads(result.stdout)


def aws_session(config):
    import boto3
    session = boto3.Session(profile_name=config["aws_profile"], region_name=config["aws_region"])
    if session.client("sts").get_caller_identity()["Account"] != config["account_id"]:
        raise RuntimeError("AWS account does not match Terraform outputs")
    return session


def save(label, value):
    folder = ROOT / "results"
    folder.mkdir(exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    path = folder / f"{label}-{stamp}.json"
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, default=str) + "\n", encoding="utf-8")
    return path
