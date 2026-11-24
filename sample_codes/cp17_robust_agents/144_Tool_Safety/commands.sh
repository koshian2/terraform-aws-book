#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# WindowsではGit Bash、macOSではbashから実行する。uvを事前に導入する。
uv sync

case "${1:-serve}" in
  serve)
    echo '購入履歴MCPを http://127.0.0.1:8000/mcp で起動します。停止はCtrl+C。'
    echo '別のターミナル: bash commands.sh check で直接検証します。'
    echo 'Codex: codex/、Claude Code: claude-code/ で起動し、/mcpで接続を確認してください。'
    uv run --frozen python app/server.py
    ;;
  check)
    uv run --frozen python scripts/client.py
    ;;
  *) echo '使い方: bash commands.sh [serve|check]' >&2; exit 2 ;;
esac
