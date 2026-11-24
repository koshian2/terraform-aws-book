# このファイルのあるディレクトリで、必要なコマンドを順に実行する。

# 準備: SSOを利用し、ログインが必要な場合に実行する。
# aws sso login --profile develop
uv sync

# AWSリソースを作成し、文書をS3へ配置する。
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan

# S3の文書をKBへ取り込む。文書更新後もapplyとsyncを再実行する。
uv run --frozen python scripts/client.py sync

# 検索原文を確認する。
uv run --frozen python scripts/client.py retrieve

# 検索結果を根拠にClaude Sonnet 4.6で回答を生成する。
# model_idを変更した場合は、上記のplanとapplyでTerraformの出力を更新してから実行する。
# モデルだけの変更なら文書の再同期は不要。
uv run --frozen python scripts/client.py ask

# 特定の会議に絞って回答を生成する。
uv run --frozen python scripts/client.py ask "第3回でコーディネーターへの支援についてどんな質問があり、事務局はどう回答しましたか？" --meeting 3 --top-k 10

# リランキングを無効にした検索結果を確認する。
uv run --frozen python scripts/client.py retrieve --reranking NONE

# 片付け: 同期・質問処理の終了後、以下を別途実行する。
# 文書用S3に追加したオブジェクトも削除対象。
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
# terraform -chdir=terraform state list
