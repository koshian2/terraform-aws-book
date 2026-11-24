# サンプル直下で区間ごとに実行する。Windows PowerShell / macOS共通。
# aws sso login --profile develop
uv sync
uv run --frozen python scripts/build.py
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan '-out=deploy.tfplan'
terraform -chdir=terraform apply deploy.tfplan

# 初回のみ。パスワードは非表示で対話入力する。
uv run --frozen python scripts/create_user.py --username regular --group regular
uv run --frozen python scripts/create_user.py --username vip --group vip

# ブラウザの既存セッションをログアウトしてから指定ユーザーでログインする。
echo 'Cognitoに regular でログインしてください。商品AがPolicyで拒否されることを確認します。'
uv run --frozen python scripts/client.py --member regular
echo 'Cognitoに vip でログインしてください。商品Aの成功、B・CのInterceptor拒否を確認します。'
uv run --frozen python scripts/client.py --member vip

# 両エージェントの設定を先に生成する。
uv run --frozen python scripts/configure_claude.py
uv run --frozen python scripts/configure_codex.py

# Codex: Cognitoで認証する。
uv run --frozen python scripts/session.py
cd codex
echo 'Cognitoに vip でログインしてください。パスワードはユーザー作成時に設定したものです。'
codex mcp login agentcore-vip-presale
# codex
cd ..

# Claude Code: /mcpから認証する。
uv run --frozen python scripts/session.py
cd claude-code
echo 'Claude Codeの /mcp から認証し、Cognitoに vip でログインしてください。'
claude
cd ..

# 接続先を作り直した場合の設定更新:
# uv run --frozen python scripts/configure_codex.py --overwrite
# uv run --frozen python scripts/configure_claude.py --overwrite

# Codexで一般会員へ切り替える場合（起動中のCodexを終了してから）:
# uv run --frozen python scripts/session.py --client codex
# cd codex
# echo 'Cognitoに regular でログインしてください。'
# codex mcp login agentcore-vip-presale
# codex
# cd ..

# 片付け: 起動中のエージェントを終了してから実行する。
# cd codex
# codex mcp logout agentcore-vip-presale
# cd ..
# cd claude-code
# claude mcp logout agentcore-vip-presale
# cd ..
# uv run --frozen python scripts/cleanup.py capture
# terraform -chdir=terraform plan -destroy '-out=destroy.tfplan'
# terraform -chdir=terraform apply destroy.tfplan
# uv run --frozen python scripts/cleanup.py leftovers
# terraform -chdir=terraform state list
