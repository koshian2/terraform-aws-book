# サンプル直下で区間ごとに実行する。Windows PowerShell / macOS共通。
# 認証の対話操作があるため、一括実行せず区間ごとに進める。
# aws sso login --profile develop
uv sync
uv run --frozen python scripts/build.py
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan '-out=deploy.tfplan'
terraform -chdir=terraform apply deploy.tfplan

# ユーザー作成は初回のみ。パスワードは非表示の対話入力。
uv run --frozen python scripts/create_user.py --username reader

# Pythonでログインし、正常・入力拒否・出力抑制の3ケースを比較する。結果はresults/に保存する。
uv run --frozen python scripts/client.py
# ブラウザを自動で開けない場合:
# uv run --frozen python scripts/client.py --no-browser

# Codexを使う場合: configureでCognitoのコールバックを自動登録し、設定を生成する。
uv run --frozen python scripts/configure_codex.py
cd codex
codex mcp login agentcore-policy
# codex
cd ..

# Claude Codeを使う場合: claude-code/をプロジェクトとして開く。
uv run --frozen python scripts/configure_claude.py
cd claude-code
claude
# /mcpでagentcore-policyを選んで認証する。
cd ..

# ターゲット登録がAuthorization errorになった場合のみ、権限と状態を確認する。
# terraform -chdir=terraform output -raw gateway_id
# aws bedrock-agentcore-control list-gateway-targets --gateway-identifier '<GATEWAY_ID>' --profile develop --region ap-northeast-1
# aws bedrock-agentcore-control synchronize-gateway-targets --gateway-identifier '<GATEWAY_ID>' --target-id-list '<TARGET_ID>' --profile develop --region ap-northeast-1
# aws bedrock-agentcore-control get-gateway-target --gateway-identifier '<GATEWAY_ID>' --target-id '<TARGET_ID>' --profile develop --region ap-northeast-1
# READYになった場合だけ失敗フラグを解除し、残りのリソースも配置する。
# terraform -chdir=terraform untaint aws_bedrockagentcore_gateway_target.inquiry
# terraform -chdir=terraform plan '-out=deploy.tfplan'
# terraform -chdir=terraform apply deploy.tfplan

# 片付け: 呼び出し元を終了し、利用したクライアントの認証情報を削除する。
# cd codex
# codex mcp logout agentcore-policy
# cd ..
# cd claude-code
# claude mcp logout agentcore-policy
# cd ..
# uv run --frozen python scripts/cleanup.py capture
# terraform -chdir=terraform plan -destroy '-out=destroy.tfplan'
# terraform -chdir=terraform apply destroy.tfplan
# uv run --frozen python scripts/cleanup.py leftovers
# terraform -chdir=terraform state list
