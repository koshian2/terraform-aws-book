# サンプル直下で区間ごとに実行する。Windows PowerShell / macOS共通。
# aws sso login --profile develop
uv sync
uv run --frozen python scripts/build.py
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan '-out=deploy.tfplan'
terraform -chdir=terraform apply deploy.tfplan

# 初回のみ。パスワードは非表示の対話入力。
uv run --frozen python scripts/create_user.py --username reader
uv run --frozen python scripts/create_user.py --username operator

# ブラウザの前回セッションを終了してから、指定したユーザーでログインする。
echo 'Cognitoに reader でログインしてください（取得は許可、クローズは拒否）。'
uv run --frozen python scripts/client.py --user reader
echo 'Cognitoに operator でログインしてください（取得後のクローズを確認します）。'
uv run --frozen python scripts/client.py --user operator

# Codex: コールバックの登録と到達確認後、セッションID付きの設定を生成する。
uv run --frozen python scripts/configure_codex.py
cd codex
echo 'Cognitoに operator でログインしてください。パスワードはcreate_user.pyで設定したものです。'
codex mcp login agentcore-temporal
# codex
cd ..

# Codexを終了してから実行。保存トークンとブラウザのログイン状態を解除し、履歴も分ける。
# uv run --frozen python scripts/session.py --client codex
# cd codex
# echo '今度はCognitoに reader でログインしてください。クローズが拒否されることを比較します。'
# codex mcp login agentcore-temporal
# codex
# cd ..
# ユーザーを変えず、新しいPolicyセッションで試す場合:
# uv run --frozen python scripts/session.py --client codex --new-session-only

# Claude Code: claude-code/をプロジェクトとして起動し、/mcpから認証する。
uv run --frozen python scripts/configure_claude.py
cd claude-code
echo 'Claude Codeの /mcp から認証し、Cognitoに operator でログインしてください。'
claude
cd ..
# Claude Codeを終了後にユーザーを切り替える場合:
# uv run --frozen python scripts/session.py --client claude
# cd claude-code
# echo '今度はCognitoに reader でログインしてください。クローズが拒否されることを比較します。'
# claude
# cd ..
# ユーザーを変えず、新しいPolicyセッションで試す場合:
# uv run --frozen python scripts/session.py --client claude --new-session-only

# 設定の再生成（コールバックや接続先の更新時）:
# uv run --frozen python scripts/configure_codex.py --overwrite
# uv run --frozen python scripts/configure_claude.py --overwrite

# ターゲット登録がAuthorization errorになった場合の再同期:
# terraform -chdir=terraform output -raw gateway_id
# aws bedrock-agentcore-control list-gateway-targets --gateway-identifier '<GATEWAY_ID>' --profile develop --region ap-northeast-1
# aws bedrock-agentcore-control synchronize-gateway-targets --gateway-identifier '<GATEWAY_ID>' --target-id-list '<TARGET_ID>' --profile develop --region ap-northeast-1
# aws bedrock-agentcore-control get-gateway-target --gateway-identifier '<GATEWAY_ID>' --target-id '<TARGET_ID>' --profile develop --region ap-northeast-1
# READY確認後だけ失敗フラグを解除して配置を再開する。
# terraform -chdir=terraform untaint aws_bedrockagentcore_gateway_target.inquiry
# terraform -chdir=terraform plan '-out=deploy.tfplan'
# terraform -chdir=terraform apply deploy.tfplan

# 片付け: 起動中のコーディングエージェントを終了してから実行する。
# cd codex
# codex mcp logout agentcore-temporal
# cd ..
# cd claude-code
# claude mcp logout agentcore-temporal
# cd ..
# uv run --frozen python scripts/cleanup.py capture
# terraform -chdir=terraform plan -destroy '-out=destroy.tfplan'
# terraform -chdir=terraform apply destroy.tfplan
# uv run --frozen python scripts/cleanup.py leftovers
# terraform -chdir=terraform state list
