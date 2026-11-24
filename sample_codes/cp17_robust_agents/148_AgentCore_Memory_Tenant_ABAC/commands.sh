#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# WindowsはGit Bash、macOSはターミナルのbashで実行する。
# SSOのログインが必要な場合に実行する。
# aws sso login --profile develop
uv sync
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan

# 短期記憶の読み書きと長期記憶の検索について、正常アクセスと越境拒否を確認する。
# 長期記憶の抽出を最大600秒待つ。未生成の場合は終了コード2で停止する。
uv run --frozen python scripts/client.py demo --output results/latest.json

# 抽出待ちの後に、会話を再投入せず記憶を確認する場合:
# ACTOR_IDとSESSION_IDはresults/latest.jsonの値に置き換える。
# uv run --frozen python scripts/client.py show --tenant tenant-a --actor ACTOR_ID --session SESSION_ID --output results/tenant-a.json
# uv run --frozen python scripts/client.py show --tenant tenant-b --actor ACTOR_ID --session SESSION_ID --output results/tenant-b.json
# showは再取得のみ。全ケースを再検証する場合は上のdemoを再実行する。

# 片付け（会話と長期記憶も削除する）:
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
# terraform -chdir=terraform state list
