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

echo 'Cognitoに reader でログインしてください。制限発生と待機後の回復を確認します。'
uv run --frozen python scripts/client.py verify
# 単発呼び出し・一覧確認も可能（それぞれブラウザで認証する）。
# uv run --frozen python scripts/client.py add --a 1 --b 2
# uv run --frozen python scripts/client.py list

# Codex: 設定生成とコールバック登録・ログイン画面の確認。
uv run --frozen python scripts/configure_codex.py
cd codex
echo 'Cognitoに reader でログインしてください。パスワードはユーザー作成時に設定したものです。'
codex mcp login agentcore-rate-limit
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
# codex mcp logout agentcore-rate-limit
# cd ..
# cd claude-code
# claude mcp logout agentcore-rate-limit
# cd ..
# uv run --frozen python scripts/cleanup.py capture
# terraform -chdir=terraform plan -destroy '-out=destroy.tfplan'
# terraform -chdir=terraform apply destroy.tfplan
# uv run --frozen python scripts/cleanup.py leftovers
# terraform -chdir=terraform state list
