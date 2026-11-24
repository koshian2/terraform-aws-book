# このファイルのあるディレクトリで、区間ごとに実行する。
# WindowsはPowerShell、macOSはターミナルで同じコマンドを使える。
# エラーが出たらそこで止める。全体を一括実行しない。

# 1. 準備と配置
# aws sso login --profile develop
uv sync
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan

# 2. CSVからHTMLレポートを作る。セッションIDはresultsに記録される。
uv run --frozen python scripts/client.py start

# 3. latestで最後に開始したセッションを指定する。過去のセッションはUUIDを指定する。
# 集計値と成果物を検算し、表示された結果フォルダのreport.htmlを確認する。
uv run --frozen python scripts/verify.py --session latest

# 4. 同じセッションで追加依頼する。
uv run --frozen python scripts/client.py ask --session latest "月別の比較表を追加し、支出が増えた費目を説明してください。"
uv run --frozen python scripts/verify.py --session latest

# 5. 任意：別セッションから入力ファイルが見えないことを確認する。
# 確認用の別セッションはコマンド内で停止する。
# uv run --frozen python scripts/client.py isolation --session latest

# 状態の記録を見る。AWS上の稼働状況を問い合わせるコマンドではない。
# uv run --frozen python scripts/client.py status --session latest
# 成果物の回収だけを再実行する（モデルの作業を再実行しない）。
# uv run --frozen python scripts/client.py fetch --session latest

# 6. 作業を終えたらセッションを停止する。
uv run --frozen python scripts/client.py stop --session latest

# 7. リソースの片付け。複数回startした場合は各セッションを先に停止する。
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
