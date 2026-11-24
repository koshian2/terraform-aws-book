"""Terraformの設定とローカルの実行記録を扱います。"""
import json
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "app"))


def settings():
    result = subprocess.run(
        ["terraform", f"-chdir={ROOT / 'terraform'}", "output", "-json", "client_config"],
        stdin=subprocess.DEVNULL, capture_output=True, encoding="utf-8", check=True, timeout=30)
    return json.loads(result.stdout)


def save(label, value):
    folder = ROOT / "results"
    folder.mkdir(exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    path = folder / f"{label}-{stamp}.json"
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, default=str) + "\n", encoding="utf-8")
    return path
