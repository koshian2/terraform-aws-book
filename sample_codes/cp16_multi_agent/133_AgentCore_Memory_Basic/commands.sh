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

# 2. 保存して、別プロセスで取得する
uv run --frozen python scripts/client.py save --session travel-001 --text "今度の旅行では京都に行きたいです"
uv run --frozen python scripts/client.py history --session travel-001
# 未使用のセッションは空のeventsになる。
uv run --frozen python scripts/client.py history --session travel-002

# 3. 履歴を使って会話する
uv run --frozen python scripts/client.py chat --session travel-001 --text "そこでは何を観光すると良い？" --show-context
uv run --frozen python scripts/client.py chat --session travel-001 --text "その中から半日で回れるプランにしてください" --show-context
uv run --frozen python scripts/client.py history --session travel-001

# 4. 片付け（保存した会話と抽出した記憶も削除する）
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
# terraform -chdir=terraform state list
