# このファイルのあるディレクトリで、区間ごとに実行する。
# WindowsはPowerShell、macOSはシェルで同じコマンドを使える。
# エラーが出た場合は、そこで止めて原因を確認する。

# 1. 準備と配置（developがSSOプロファイルの場合）
# aws sso login --profile develop
uv sync
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan

# 2. Pythonで実行する場合
uv run --frozen python scripts/client.py demo --mode minimal

# 段階ごとに操作する場合（CASE_IDとREVISIONを実際の値に置換）
# uv run --frozen python scripts/client.py create --mode minimal
# uv run --frozen python scripts/client.py talk CASE_ID
# uv run --frozen python scripts/client.py handoff CASE_ID
# uv run --frozen python scripts/client.py advance CASE_ID --revision REVISION
# uv run --frozen python scripts/client.py status CASE_ID
# uv run --frozen python scripts/client.py talk CASE_ID

# 3. コーディングエージェントから使う場合
# サーバーはCtrl+Cで停止する。このターミナルを開いたまま接続する。
uv run --frozen python server.py

# 別のターミナルでサンプル直下から、使うエージェントの区間だけ実行する。
# Codex：設定を読み込み、MCPのツール一覧を確認してREADMEの依頼例を入力する。
# cd codex
# codex

# Claude Code：設定を読み込み、/mcpで接続状態を確認してREADMEの依頼例を入力する。
# cd claude-code
# claude

# 4. 片付け（サンプル直下で、必要なときだけコメントを外して順に実行）
# サンプルのAWS上の入力・生成結果も削除する。
# uv run --frozen python scripts/cleanup.py capture
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
# uv run --frozen python scripts/cleanup.py leftovers
