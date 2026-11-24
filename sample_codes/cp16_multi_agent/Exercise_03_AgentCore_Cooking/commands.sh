# このファイルのあるディレクトリで、区間ごとに実行する。
# WindowsはPowerShell、macOSはシェルで同じコマンドを使える。
# エラーが出たらそこで止める。全体を一括実行しない。

# 1. 準備と配置
# aws sso login --profile develop
uv sync
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan

# 2. S3へ配置された30件のレシピをKBへ取り込む
# レシピを編集した場合もplan・applyの後に実行する。
uv run --frozen python scripts/client.py sync

# 3. PythonからリモートMCPへ直接接続して確認する場合
uv run --frozen python scripts/client.py start "鶏肉とキャベツで、薄味の主菜を1品教えてください"
# 上の結果のsession_idをSESSION_IDに置き換える。
# uv run --frozen python scripts/client.py ask SESSION_ID "それ、どう作るんだっけ？"
# uv run --frozen python scripts/client.py ask SESSION_ID "鶏肉とキャベツを切りました。このあとどうする？"
# uv run --frozen python scripts/client.py history SESSION_ID
uv run --frozen python scripts/client.py list

# 4. Codex / Claude Codeから使う場合
# 中継プロキシをこのターミナルで起動しておく。停止はCtrl+C。
# Runtime側のツール定義を取得するため、AWSのログイン状態も確認する。
uv run --frozen python server.py

# 別のターミナルで、サンプル直下から使うエージェントの区間だけ実行する。
# cd codex
# codex
# 接続確認後、READMEのプロンプトを入力する。

# cd claude-code
# claude
# /mcpで接続を確認し、READMEのプロンプトを入力する。

# 5. 片付け（サーバーを停止し、サンプル直下で実行）
# 保存された会話、レシピ、ベクトル、コードを含めて削除する。
# uv run --frozen python scripts/cleanup.py capture
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
# uv run --frozen python scripts/cleanup.py leftovers
