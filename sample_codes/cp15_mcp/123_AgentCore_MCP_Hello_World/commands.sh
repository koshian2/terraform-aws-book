# このファイルのあるディレクトリで、必要なコマンドを順に実行する。
# 一括実行せず、サーバーや中継を起動する箇所は別ターミナルを使う。
# WindowsのPowerShellとmacOSのターミナルで同じコマンドを使える。

# 1. 準備。SSOのログインが必要な場合だけコメントを外す。
# aws sso login --profile develop
uv sync

# 2. AWSに配置するZIPを作る。コード・依存変更後も再実行する。
uv run --frozen python scripts/build.py

# 3. AWSリソースを作る。
terraform -chdir=terraform init
terraform -chdir=terraform fmt -check
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan

# 4. AWS上のhello_worldを直接呼び出す。
uv run --frozen python scripts/client.py

# 呼び出し権限が不足する場合に、付与するポリシー例を表示する。
# terraform -chdir=terraform output -raw invoke_policy_json

# 5. エージェント用のHTTP中継を起動する。このターミナルは開いたままにする。
uv run --frozen python scripts/proxy.py

# 6. 別ターミナルで中継を確認後、エージェントごとのフォルダを開いて接続する。
uv run --frozen python scripts/client.py --url http://127.0.0.1:8001/mcp

# 任意: AWSへの配置前にローカルだけで確認する。
# ターミナルAで起動する。
# uv run --frozen python server.py
# ターミナルBで呼び出す。
# uv run --frozen python scripts/client.py --url http://127.0.0.1:8000/mcp
# 中継もローカルで確認する場合はターミナルCで起動し、上記6を実行する。
# uv run --frozen python scripts/proxy.py --url http://127.0.0.1:8000/mcp

# 片付け: 中継とローカルサーバーをCtrl+Cで止めてから実行する。
# build/を削除済みなら、先に上記2でZIPを再作成する。
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
# terraform -chdir=terraform state list
