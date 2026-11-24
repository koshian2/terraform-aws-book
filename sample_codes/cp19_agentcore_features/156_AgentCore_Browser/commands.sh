# このファイルのあるディレクトリで、区間ごとに実行する。
# WindowsはPowerShell、macOSはターミナルで同じコマンドを使える。
# エラーが出たらそこで止める。全体を一括実行しない。

# 1. 準備と配置
# aws sso login --profile develop
uv sync
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan

# 2. ローカルMCPサーバーを起動（このターミナルを開いたままにする）
uv run --frozen python server.py

# 3. 別のターミナルで、サンプル直下から使うエージェントの区間だけ実行する。
# CodexとClaude Codeを同時に接続しない。
# cd codex
# codex
# /mcpでagentcore-browserの7ツールを確認し、READMEのプロンプトを入力する。

# cd claude-code
# claude
# /mcpでagentcore-browserの接続を確認し、READMEのプロンプトを入力する。

# 4. 片付け
# エージェントにブラウザの終了を依頼し、AWSコンソールで終了を確認する。
# MCPサーバーのターミナルでCtrl+Cを押し、サンプル直下で以下を実行する。
# S3の操作記録も削除する。必要な記録は先に保存する。
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
