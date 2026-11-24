#!/usr/bin/env bash
# Windows: Git Bash、macOS: ターミナル。サンプル直下で実行する。
set -euo pipefail
# 必要な場合だけ再ログインする。
# aws sso login --profile develop
uv sync
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan

# 不具合あり・修正後の会話を実行する。評価APIは呼び出さない。
uv run --frozen python scripts/client.py
# 評価は非同期。未到着なら、この行だけ再実行する。
uv run --frozen python scripts/observe.py --wait-seconds 900

# オンライン評価を一時停止する場合（エージェントは残る）。
# terraform -chdir=terraform apply -var='evaluation_enabled=false'

# 片付け。
# uv run --frozen python scripts/cleanup.py capture
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
# uv run --frozen python scripts/cleanup.py leftovers
# terraform -chdir=terraform state list
