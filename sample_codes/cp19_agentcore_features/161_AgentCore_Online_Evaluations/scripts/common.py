"""Terraformから公開設定だけを読みます。"""
import sys
import json
from pathlib import Path
import subprocess

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[1]


def settings():
    result = subprocess.run(
        ["terraform", f"-chdir={ROOT / 'terraform'}", "output", "-json", "client_config"],
        capture_output=True, text=True, encoding="utf-8", check=True,
    )
    return json.loads(result.stdout)
