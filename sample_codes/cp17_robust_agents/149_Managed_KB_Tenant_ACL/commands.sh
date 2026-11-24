#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# WindowsはGit Bash、macOSはbash。必要な場合にSSOへログインする。
# aws sso login --profile develop
uv sync
uv run --frozen python scripts/build.py
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan

# 文書とACLを同期し、管理者が検索条件とACLを個別に検証する。
uv run --frozen python scripts/client.py sync
uv run --frozen python scripts/client.py verify-admin

# 既存ユーザーは所属・メールが一致すればスキップ。パスワードは非表示入力。
uv run --frozen python scripts/create_user.py --username alice
uv run --frozen python scripts/create_user.py --username ann
uv run --frozen python scripts/create_user.py --username bob

echo 'Cognitoにalice（A社・契約管理者）でログインしてください。'
uv run --frozen python scripts/client.py verify-gateway --username alice
echo 'Cognitoにann（A社・一般担当者）でログインしてください。'
uv run --frozen python scripts/client.py verify-gateway --username ann
echo 'Cognitoにbob（B社・契約管理者）でログインしてください。'
uv run --frozen python scripts/client.py verify-gateway --username bob

# OAuthのコールバックを登録し、各プロジェクトの接続設定を生成する。
uv run --frozen python scripts/configure_codex.py --overwrite
uv run --frozen python scripts/configure_claude.py --overwrite

# Codexを試す場合:
# uv run --frozen python scripts/session.py
# cd codex
# echo 'Cognitoにaliceでログインしてください。'
# codex mcp login agentcore-kb-tenant
# codex
# cd ..

# Claude Codeを試す場合:
# uv run --frozen python scripts/session.py
# cd claude-code
# echo '/mcpで認証し、Cognitoにaliceでログインしてください。'
# claude
# cd ..

# Codexでannまたはbobへ切り替える場合（起動中のエージェントを終了）:
# uv run --frozen python scripts/session.py --client codex
# cd codex
# echo 'Cognitoにann（またはbob）でログインしてください。'
# codex mcp login agentcore-kb-tenant
# codex
# cd ..

# Claude Codeで切り替える場合（起動中のエージェントを終了）:
# cd claude-code
# claude mcp logout agentcore-kb-tenant
# cd ..
# uv run --frozen python scripts/session.py
# cd claude-code
# echo '/mcpで認証し、Cognitoにann（またはbob）でログインしてください。'
# claude
# cd ..

# 片付け（文書・ユーザー・KBも削除する）:
# cd codex
# codex mcp logout agentcore-kb-tenant
# cd ..
# cd claude-code
# claude mcp logout agentcore-kb-tenant
# cd ..
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
# terraform -chdir=terraform state list
