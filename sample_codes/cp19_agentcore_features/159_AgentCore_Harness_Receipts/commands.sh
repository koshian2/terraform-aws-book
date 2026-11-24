# このファイルのあるディレクトリで、区間ごとに実行する。
# WindowsはPowerShell、macOSはターミナルで同じコマンドを使える。
# エラーが出たらそこで止める。全体を一括実行しない。

# 1. 準備と配置
# aws sso login --profile develop
uv sync
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=deploy.tfplan
terraform -chdir=terraform apply deploy.tfplan

# 2. 同梱の領収書画像を送り、暫定の経費明細と確認事項を作る。
uv run --frozen python scripts/client.py start

# 3. 初回の結果を検算する。latestは最後に開始したセッションを選ぶ。
uv run --frozen python scripts/verify.py --session latest --phase initial

# 4. 用途と重複への回答を同じセッションに送り、更新結果を検算する。
uv run --frozen python scripts/client.py ask --session latest "04.pngの飲食代は取引先との打ち合わせです。05.pngは01.pngを重複して取り込んだコピーなので、01.pngだけ計上してください。"
uv run --frozen python scripts/verify.py --session latest --phase final

# 状態の記録を見る。AWS上の稼働状況を問い合わせるコマンドではない。
# uv run --frozen python scripts/client.py status --session latest
# 成果物の回収だけを再実行する。モデルの作業は再実行しない。
# uv run --frozen python scripts/client.py fetch --session latest

# 5. 作業を終えたらセッションを停止する。
uv run --frozen python scripts/client.py stop --session latest

# 6. リソースの片付け。複数回startした場合は各UUIDを指定して先に停止する。
# Skill用S3バケット内のオブジェクトも削除される。
# terraform -chdir=terraform plan -destroy -out=destroy.tfplan
# terraform -chdir=terraform apply destroy.tfplan
