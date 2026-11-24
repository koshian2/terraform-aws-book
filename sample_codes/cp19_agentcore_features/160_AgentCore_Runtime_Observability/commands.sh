#!/usr/bin/env bash
# サンプル直下で実行する。WindowsはGit Bash、macOSはターミナルを使う。
set -euo pipefail

# 必要な場合だけログインする。
# aws sso login --profile develop
uv sync
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan

# 登録済みなら既存のパスワードを使う。
uv run --frozen python scripts/create_user.py --username reader
echo 'ブラウザでCognitoに reader としてログインしてください。'
uv run --frozen python scripts/client.py
uv run --frozen python scripts/observe.py

# スパンが未到着なら、ツールを呼び直さず観測だけを再実行する。
# uv run --frozen python scripts/observe.py --wait-seconds 900

# 片付け。
# uv run --frozen python scripts/cleanup.py capture
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
# uv run --frozen python scripts/cleanup.py leftovers
# terraform -chdir=terraform state list
