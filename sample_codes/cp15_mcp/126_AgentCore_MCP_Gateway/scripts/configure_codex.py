"""Terraformの出力をCodex用フォルダに配置します。認証情報は含みません。"""
import argparse
import subprocess
from common import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--overwrite", action="store_true", help="生成済み設定を更新する")
    args = parser.parse_args()
    target = ROOT / "codex/.codex/config.toml"
    if target.exists() and not args.overwrite:
        raise SystemExit("設定が既にあります。更新する場合は--overwriteを指定してください。")
    result = subprocess.run(
        ["terraform", f"-chdir={ROOT / 'terraform'}", "output", "-raw", "codex_mcp_config"],
        check=True, capture_output=True, text=True, encoding="utf-8",
    )
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(result.stdout, encoding="utf-8")
    print(f"Created {target}")


if __name__ == "__main__":
    main()
