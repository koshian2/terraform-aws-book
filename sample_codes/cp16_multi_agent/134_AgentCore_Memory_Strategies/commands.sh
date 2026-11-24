# このファイルのあるディレクトリで、区間ごとに実行する。
# WindowsはPowerShell、macOSはシェルで同じコマンドを使える。
# エラーが出た場合は、その時点で止めて原因を確認する。

# 1. 準備と配置
# SSOのログインが必要な場合に実行する。
# aws sso login --profile develop
uv sync
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan

# 2. 会話を保存して4戦略の抽出結果を最大600秒待つ
uv run --frozen python scripts/client.py demo --output results/latest.json

# 3. 後から再取得する場合（会話を再投入しない）
# ACTOR_IDをdemoが表示したactor_idへ置き換える。
# 終了コード2は観測時間内に全戦略の記憶が揃わなかったことを表す。
# 同じactor_idでshowを実行して確認する。
# uv run --frozen python scripts/client.py show --actor ACTOR_ID --wait-seconds 600 --output results/retrieved.json

# 4. 片付け（保存した会話と抽出した記憶も削除する）
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
# terraform -chdir=terraform state list
