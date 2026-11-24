"""Terraformの公開設定からClaude Codeの.mcp.jsonを生成します。"""
import uuid
import argparse
import json
import subprocess
from common import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--overwrite", action="store_true", help="生成済み設定を更新する")
    args = parser.parse_args()
    target = ROOT / "claude-code/.mcp.json"
    if target.exists() and not args.overwrite:
        raise SystemExit("設定が既にあります。更新する場合は--overwriteを指定してください。")
    result = subprocess.run(
        ["terraform", f"-chdir={ROOT / 'terraform'}", "output", "-raw", "claude_mcp_config"],
        check=True, capture_output=True, text=True, encoding="utf-8",
    )
    config = json.loads(result.stdout.replace("REPLACE-WITH-UUID", str(uuid.uuid4())))
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Created {target}")


if __name__ == "__main__":
    main()
