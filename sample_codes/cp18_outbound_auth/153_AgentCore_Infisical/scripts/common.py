"""Read public Terraform outputs."""
import json
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
def terraform():
    return "terraform"
def settings():
    result = subprocess.run([terraform(), "output", "-json", "client_config"],
        cwd=ROOT / "terraform", capture_output=True, text=True, encoding="utf-8", check=True)
    return json.loads(result.stdout)
