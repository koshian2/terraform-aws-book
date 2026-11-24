# このファイルのあるディレクトリで、区間ごとに実行する。
# WindowsはPowerShell、macOSはターミナルで同じコマンドを使える。
# エラーが出たらそこで止める。全体を一括実行しない。

# 1. 準備と配置
# aws sso login --profile develop
uv sync
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan

# 2. ローカルMCPを起動したままにする（停止はCtrl+C）
uv run --frozen python server.py

# 3. 別のターミナルで、サンプル直下からどちらか一方を起動する。
# cd codex
# codex
# /mcpでagentcore-code-interpreterの6ツールを確認し、READMEの依頼例を入力する。

# cd claude-code
# claude
# /mcpで接続を確認し、READMEの依頼例を入力する。

# 4. シフト表をダウンロードした後、サンプル直下の別ターミナルで検算する。
uv run --frozen python scripts/verify.py
# 追加の希望休を指定して作り直した場合の例
# uv run --frozen python scripts/verify.py --off 佐藤:水

# 5. 片付け
# エージェントにセッション終了を依頼し、サーバーをCtrl+Cで停止する。
# AWSコンソールでセッションの終了を確認してから削除する。
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
