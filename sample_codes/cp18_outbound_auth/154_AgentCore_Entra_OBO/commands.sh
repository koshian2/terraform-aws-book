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
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan
uv run --frozen python scripts/client.py --report
# 別の2ユーザー（A、B）で照合し、不正トークンなどの拒否も確認します。
# uv run --frozen python scripts/client.py --two-users --negative --report

# どちらかのランチャーから起動します。利用者変更・期限切れ時も再実行します。
# uv run --frozen python scripts/launch_agent.py codex
# uv run --frozen python scripts/launch_agent.py claude

# 後片付け（削除対象をplanで確認してから実行）
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
