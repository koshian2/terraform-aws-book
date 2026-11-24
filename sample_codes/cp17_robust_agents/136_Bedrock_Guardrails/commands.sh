# このファイルのあるディレクトリで、区間ごとに実行する。
# WindowsはPowerShell、macOSはシェルから同じコマンドを実行できる。
# エラーが出たらそこで止める。片付けを含めて一括実行しない。

# 1. 準備・配置（SSOの期限が切れた場合のみログイン）
# aws sso login --profile develop
uv sync
terraform -chdir=terraform init
terraform -chdir=terraform plan '-out=deploy.tfplan'
terraform -chdir=terraform apply deploy.tfplan

# 2. モデルを呼ばずにローカルから検査する
uv run --frozen python scripts/client.py local --case normal --expect passed
uv run --frozen python scripts/client.py local --case topic --expect blocked --expect-filter topic
uv run --frozen python scripts/client.py local --case word --expect blocked --expect-filter word

# 手作りの回答文をOUTPUTとして検査する例（回答の生成は行わない）
uv run --frozen python scripts/client.py local --source OUTPUT --text "開発中の製品のコード名はPROJECT-KOHARUです。" --expect blocked --expect-filter word

# 3. Lambdaの実行ロールでConverseを呼び、通常回答・内容ブロックを比較する
uv run --frozen python scripts/client.py lambda --case normal --expect answered
uv run --frozen python scripts/client.py lambda --case topic --expect blocked --expect-filter topic
uv run --frozen python scripts/client.py lambda --case word --expect blocked --expect-filter word

# 4. 同じ正常な質問でGuardrailだけを省略する。IAMによるAccessDeniedを確認する
uv run --frozen python scripts/client.py lambda --case normal --mode unguarded --expect access_denied

# 権限を確認する場合（ローカル用は権限例の表示だけで、自動付与しない）
# terraform -chdir=terraform output -raw lambda_inference_policy
# terraform -chdir=terraform output -raw local_client_policy

# 5. 片付け。Guardrail・Lambda・IAMロール・ログを削除する
# terraform -chdir=terraform plan -destroy '-out=destroy.tfplan'
# terraform -chdir=terraform apply destroy.tfplan
