# このファイルのあるディレクトリで、コマンドを順に実行する。
# WindowsのPowerShell、macOSのターミナルで同じコマンドを使える。
# SSOのログインが必要な場合だけ実行する。
# aws sso login --profile develop

# 準備
uv sync

# デプロイ。CloudFrontの作成には数分かかる。
terraform -chdir=terraform init
terraform -chdir=terraform fmt -check
terraform -chdir=terraform validate
terraform -chdir=terraform plan '-out=deploy.tfplan'
terraform -chdir=terraform apply deploy.tfplan

# デモ用ユーザーを作成。パスワードは対話入力する。
uv run --frozen python scripts/client.py create-user --username reader

# 表示されたURLをブラウザで開く。
terraform -chdir=terraform output -raw web_url
# 「ログイン」→readerでログインし、ID・アクセストークンの中身を確認。
# 「トークンを更新」でexpなどを比較し、「ログアウト」で戻る。

# boto3による認証・JWT検証・更新・失効を順に確認する。
uv run --frozen python scripts/client.py tokens --username reader

# HTML・JavaScript変更後はplan、applyを再実行する。

# 片付け: ユーザープール内のユーザーも削除される。
# terraform -chdir=terraform plan -destroy '-out=destroy.tfplan'
# terraform -chdir=terraform apply destroy.tfplan
# terraform -chdir=terraform state list
