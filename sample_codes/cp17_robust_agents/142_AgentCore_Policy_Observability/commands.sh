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

# 同じ呼び出しを再実行せず、2件の判定をトレースと照合する。
echo 'Cognitoに reader でログインしてください。1+2は許可、101+2は拒否されることを確認します。'
uv run --frozen python scripts/client.py
uv run --frozen python scripts/observe.py
# 未到着なら観測だけを再実行する。
# uv run --frozen python scripts/observe.py --wait-seconds 900

# Codex: 設定生成とコールバック登録・ログイン画面の確認。
uv run --frozen python scripts/configure_codex.py
cd codex
echo 'Cognitoに reader でログインしてください。パスワードはユーザー作成時に設定したものです。'
codex mcp login agentcore-policy-observability
# codex
cd ..

# Claude Code: /mcpから認証する。
uv run --frozen python scripts/configure_claude.py
cd claude-code
echo 'Claude Codeの /mcp から認証し、Cognitoに reader でログインしてください。'
claude
cd ..

# 接続先を作り直した場合の設定更新:
# uv run --frozen python scripts/configure_codex.py --overwrite
# uv run --frozen python scripts/configure_claude.py --overwrite

# 片付け: 起動中のエージェントを終了してから実行する。
# cd codex
# codex mcp logout agentcore-policy-observability
# cd ..
# cd claude-code
# claude mcp logout agentcore-policy-observability
# cd ..
# uv run --frozen python scripts/cleanup.py capture
# terraform -chdir=terraform plan -destroy '-out=destroy.tfplan'
# terraform -chdir=terraform apply destroy.tfplan
# uv run --frozen python scripts/cleanup.py leftovers
# terraform -chdir=terraform state list
