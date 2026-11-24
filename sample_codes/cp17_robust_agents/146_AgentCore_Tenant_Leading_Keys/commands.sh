#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# サンプル直下で区間ごとに実行する。WindowsはGit Bash、macOSはbashで実行できる。
# aws sso login --profile develop
uv sync
uv run --frozen python scripts/build.py
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan '-out=deploy.tfplan'
terraform -chdir=terraform apply deploy.tfplan

# 初回のみ。管理者が所属を指定する。パスワードは非表示で入力する。
uv run --frozen python scripts/create_user.py --username alice --tenant tenant-a
uv run --frozen python scripts/create_user.py --username bob --tenant tenant-b

# ログインごとにブラウザのCognitoセッションを終了して取り違えを防ぐ。
echo 'Cognitoに alice でログインしてください。A社の問い合わせを確認します。'
uv run --frozen python scripts/client.py --username alice --tenant tenant-a
echo 'Cognitoに bob でログインしてください。B社の問い合わせを確認します。'
uv run --frozen python scripts/client.py --username bob --tenant tenant-b

# 両エージェントの設定を生成し、Cognitoのコールバック登録の反映も確認する。
uv run --frozen python scripts/configure_claude.py
uv run --frozen python scripts/configure_codex.py

# Codex
uv run --frozen python scripts/session.py
cd codex
echo 'Cognitoに alice でログインしてください。'
codex mcp login agentcore-leading-keys
# codex
cd ..

# Claude Code
uv run --frozen python scripts/session.py
cd claude-code
echo 'Claude Codeの /mcp から認証し、Cognitoに alice でログインしてください。'
claude
cd ..

# 接続先を作り直した場合:
# uv run --frozen python scripts/configure_codex.py --overwrite
# uv run --frozen python scripts/configure_claude.py --overwrite

# Codexでbobへ切り替える場合（起動中のCodexを終了してから）:
# uv run --frozen python scripts/session.py --client codex
# cd codex
# echo 'Cognitoに bob でログインしてください。'
# codex mcp login agentcore-leading-keys
# codex
# cd ..

# Claude Codeでbobへ切り替える場合（起動中のClaude Codeを終了してから）:
# cd claude-code
# claude mcp logout agentcore-leading-keys
# cd ..
# uv run --frozen python scripts/session.py
# cd claude-code
# echo 'Claude Codeの /mcp から認証し、Cognitoに bob でログインしてください。'
# claude
# cd ..

# 片付け: エージェントを終了してから実行する。
# cd codex
# codex mcp logout agentcore-leading-keys
# cd ..
# cd claude-code
# claude mcp logout agentcore-leading-keys
# cd ..
# uv run --frozen python scripts/cleanup.py capture
# terraform -chdir=terraform plan -destroy '-out=destroy.tfplan'
# terraform -chdir=terraform apply destroy.tfplan
# uv run --frozen python scripts/cleanup.py leftovers
# terraform -chdir=terraform state list
