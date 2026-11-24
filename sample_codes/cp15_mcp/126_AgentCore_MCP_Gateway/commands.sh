# このファイルのあるディレクトリで、必要なコマンドを順に実行する。
# Windows PowerShell / macOS共通。一括実行せず、対話操作の区切りで止める。
# aws sso login --profile develop
uv sync
uv run --frozen python scripts/build.py
terraform -chdir=terraform init
terraform -chdir=terraform fmt -check
terraform -chdir=terraform validate
terraform -chdir=terraform plan '-out=deploy.tfplan'
terraform -chdir=terraform apply deploy.tfplan

# helloターゲットの初回登録がAuthorization errorで失敗した場合のみ。
# IAM権限とRuntimeの状態を確認し、以下の<GATEWAY_ID>と<TARGET_ID>を実際の値に置き換える。
# terraform -chdir=terraform output -raw gateway_id
# aws bedrock-agentcore-control list-gateway-targets --gateway-identifier '<GATEWAY_ID>' --profile develop --region ap-northeast-1
# aws bedrock-agentcore-control synchronize-gateway-targets --gateway-identifier '<GATEWAY_ID>' --target-id-list '<TARGET_ID>' --profile develop --region ap-northeast-1
# aws bedrock-agentcore-control get-gateway-target --gateway-identifier '<GATEWAY_ID>' --target-id '<TARGET_ID>' --profile develop --region ap-northeast-1
# statusがREADYになった場合だけ、helloの失敗フラグを解除してステートを更新する。
# terraform -chdir=terraform untaint aws_bedrockagentcore_gateway_target.hello
# terraform -chdir=terraform plan -refresh-only '-out=recovery.tfplan'
# terraform -chdir=terraform apply recovery.tfplan
# terraform -chdir=terraform plan

# ユーザーの作成（初回のみ）。パスワードは非表示で対話入力。
uv run --frozen python scripts/create_user.py --username reader

# Pythonで一覧・Hello World・Lambdaの足し算・AWSドキュメント検索を確認する。
uv run --frozen python scripts/client.py
# 自動でブラウザが開かない場合:
# uv run --frozen python scripts/client.py --no-browser
# 検索語を変える場合:
# uv run --frozen python scripts/client.py --query "Amazon Bedrock AgentCore Gateway"

# Codexのプロジェクト設定を生成し、そのフォルダでログインする。
uv run --frozen python scripts/configure_codex.py
cd codex
codex mcp login agentcore-gateway
# 未登録redirect_uriで止まる場合はCtrl+Cで終了し、READMEの初回設定を行う。
cd ..

# codex_oauth_callback_urlをterraform/terraform.tfvarsへ設定した後の更新:
# terraform -chdir=terraform plan '-out=deploy.tfplan'
# terraform -chdir=terraform apply deploy.tfplan
# uv run --frozen python scripts/configure_codex.py --overwrite
# cd codex
# codex mcp login agentcore-gateway
# codex
# cd ..

# Claude Codeを使う場合（既存環境も先に冒頭のplan・applyでコールバックを登録する）。
uv run --frozen python scripts/configure_claude.py
# 再生成時は末尾に --overwrite を付ける。
cd claude-code
claude
# 初回はプロジェクトと.mcp.jsonの利用を確認し、/mcp で
# agentcore-gatewayを選んで認証する。認証後はREADMEの3種類の依頼例を試す。
# Claude Code終了後、再ログインだけ行う場合:
# claude mcp login agentcore-gateway
cd ..

# ローカル確認はHello World MCPのみ。サーバーを別ターミナルで起動する。
# uv run --frozen python server.py
# uv run --frozen python scripts/client.py --local

# 片付け: 呼び出しを終了し、CodexのOAuth認証情報も削除する。
# Claude Codeを使った場合:
# cd claude-code
# claude mcp logout agentcore-gateway
# cd ..
# cd codex
# codex mcp logout agentcore-gateway
# cd ..
# terraform -chdir=terraform plan -destroy '-out=destroy.tfplan'
# 保存した削除プランを適用し、Runtimeが自動作成したロググループも削除する。
# uv run --frozen python scripts/cleanup.py --apply
# terraform -chdir=terraform state list
