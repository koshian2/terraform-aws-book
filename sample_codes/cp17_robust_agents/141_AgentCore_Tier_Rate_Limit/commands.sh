# サンプル直下で区間ごとに実行する。Windows PowerShell / macOS共通。
# aws sso login --profile develop
uv sync
uv run --frozen python scripts/build.py
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan '-out=deploy.tfplan'
terraform -chdir=terraform apply deploy.tfplan

# 初回のみ。各ユーザーのパスワードは非表示の対話入力。
uv run --frozen python scripts/create_user.py --username alice --tenant tenant-a
uv run --frozen python scripts/create_user.py --username alice2 --tenant tenant-a
uv run --frozen python scripts/create_user.py --username bob --tenant tenant-b
uv run --frozen python scripts/create_user.py --username carol --tenant tenant-c

echo 'Cognitoに alice（Free）、次にcarol（Pro）でログインします。'
uv run --frozen python scripts/client.py verify --user alice
uv run --frozen python scripts/client.py verify --user carol

# テナントの共有・分離をまとめて観察する場合（他のクライアントの呼び出しは止める）:
# echo 'alice、alice2、bob、carolの順に4人分ログインします。案内に従ってください。'
# uv run --frozen python scripts/compare.py
# 単発の確認:
# uv run --frozen python scripts/client.py add --user bob --a 1 --b 2

uv run --frozen python scripts/configure_codex.py
uv run --frozen python scripts/session.py
cd codex
echo 'Cognitoに alice（tenant-a / Free）でログインしてください。'
codex mcp login agentcore-tier-rate-limit
# codex
cd ..
# Codexを終了してからProへ切り替える:
# uv run --frozen python scripts/session.py --client codex
# cd codex
# echo 'Cognitoに carol（tenant-c / Pro）でログインしてください。'
# codex mcp login agentcore-tier-rate-limit
# codex
# cd ..

uv run --frozen python scripts/configure_claude.py
uv run --frozen python scripts/session.py
cd claude-code
echo 'Claude Codeの /mcp から認証し、Cognitoに alice（Free）でログインしてください。'
claude
cd ..
# Proへ切り替える場合、Claude Codeの /mcp で対象の認証を解除して終了する。
# uv run --frozen python scripts/session.py
# cd claude-code
# echo '/mcp から再認証し、Cognitoに carol（Pro）でログインしてください。'
# claude
# cd ..

# 接続先を作り直した場合の設定更新:
# uv run --frozen python scripts/configure_codex.py --overwrite
# uv run --frozen python scripts/configure_claude.py --overwrite

# 片付け: CodexのOAuthログアウト、Claude Codeの /mcp での認証解除後に終了する。
# cd codex
# codex mcp logout agentcore-tier-rate-limit
# cd ..
# uv run --frozen python scripts/cleanup.py capture
# terraform -chdir=terraform plan -destroy '-out=destroy.tfplan'
# terraform -chdir=terraform apply destroy.tfplan
# uv run --frozen python scripts/cleanup.py leftovers
# terraform -chdir=terraform state list
