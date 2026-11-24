#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# AWSの認証が期限切れの場合に実行します。
# aws sso login --profile develop
uv sync
if [[ ! -f terraform/terraform.tfvars ]]; then
  cp terraform/terraform.tfvars.example terraform/terraform.tfvars
  echo "terraform/terraform.tfvarsを編集してから再実行してください。"
  exit 1
fi
uv run --frozen python scripts/build.py
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan
uv run --frozen python scripts/finalize.py
uv run --frozen python scripts/setup_github.py
read -r -p "表示されたGitHub callbackをAppへ登録したらEnter: "
uv run --frozen python scripts/setup_github.py --configure
uv run --frozen python scripts/create_user.py --username reader
echo "Cognitoへのログイン: reader / 作成時に指定したパスワード"
uv run --frozen python scripts/configure_codex.py --overwrite
uv run --frozen python scripts/configure_claude.py --overwrite
uv run --frozen python scripts/client.py portal
read -r -p "上のポータルでreaderとしてログインしGitHub接続に同意したらEnter: "
AGENTCORE_ACCESS_TOKEN="$(uv run --frozen python scripts/login.py)"
export AGENTCORE_ACCESS_TOKEN
trap 'unset AGENTCORE_ACCESS_TOKEN' EXIT
uv run --frozen python scripts/client.py list
read -r -p "取得する検証用Issue番号 [1]: " issue_number
uv run --frozen python scripts/client.py get "${issue_number:-1}"
unset AGENTCORE_ACCESS_TOKEN

# Codex: 別途以下を実行します（Cognitoはreader）。
# cd codex
# codex mcp login agentcore-github-consent
# codex
# cd ..
# Claude Code: claude-code/で起動し、/mcpから認証します。
# cd claude-code
# claude
# cd ..

# 後片付け（削除対象をplanで確認してから実行）
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
