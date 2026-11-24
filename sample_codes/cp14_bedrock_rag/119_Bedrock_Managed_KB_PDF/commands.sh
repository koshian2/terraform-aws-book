# このファイルのあるディレクトリで、必要なコマンドを順に実行する。

# 準備: SSOを利用し、ログインが必要な場合に実行する。
# aws sso login --profile develop
uv sync

# 公式サイトから全10ページの原本PDFを取得する。
curl --fail --location --output documents/relocation-direction.pdf https://www.mlit.go.jp/policy/shingikai/content/001705261.pdf

# AWSリソースを作成し、PDFとメタデータをS3へ配置する。
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan

# PDFをKBへ取り込む。文書更新後もapplyとsyncを再実行する。
uv run --frozen python scripts/client.py sync

# 円グラフについて、まず検索されたテキストを確認する。
uv run --frozen python scripts/client.py retrieve

# 検索結果を根拠にClaude Sonnet 4.6で回答を生成する。
# model_id変更後はplanとapplyで出力を更新する。モデルのみの変更なら再同期は不要。
uv run --frozen python scripts/client.py ask

# 分類図のラベルと人数、関係を尋ねる。
uv run --frozen python scripts/client.py ask "訪問系の関係人口の5つの分類と、それぞれの推計人数を対応させて示してください。図の地域との結びつきの強さはどう表されていますか？"

# 資料外の質問への回答を確認する。
uv run --frozen python scripts/client.py ask "この資料から2026年時点の関係人口の実測値を教えてください。"

# リランキングを無効にした検索結果を確認する。
uv run --frozen python scripts/client.py retrieve --reranking NONE

# 片付け: 同期・質問処理の終了後、以下を別途実行する。
# 文書用S3に追加したオブジェクトも削除対象。
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
# terraform -chdir=terraform state list
