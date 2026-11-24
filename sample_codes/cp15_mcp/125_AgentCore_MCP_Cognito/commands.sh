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

# ユーザーの作成（初回のみ）。パスワードは非表示で対話入力。
uv run --frozen python scripts/create_user.py --username reader

# Pythonでログインからツール呼び出しまで確認する。
uv run --frozen python scripts/client.py
# 自動でブラウザが開かない場合:
# uv run --frozen python scripts/client.py --no-browser

# Codexのプロジェクト設定を生成し、そのフォルダでログインする。
uv run --frozen python scripts/configure_codex.py
cd codex
codex mcp login agentcore-cognito
# 未登録redirect_uriで止まる場合はCtrl+Cで終了し、READMEの初回設定を行う。
cd ..

# codex_oauth_callback_urlをterraform/terraform.tfvarsへ設定した後の更新:
# terraform -chdir=terraform plan '-out=deploy.tfplan'
# terraform -chdir=terraform apply deploy.tfplan
# uv run --frozen python scripts/configure_codex.py --overwrite
# cd codex
# codex mcp login agentcore-cognito
# codex
# cd ..

# Claude Codeを使う場合（既存環境も先に冒頭のplan・applyでコールバックを登録する）。
uv run --frozen python scripts/configure_claude.py
# 再生成時は末尾に --overwrite を付ける。
cd claude-code
claude
# 初回はプロジェクトと.mcp.jsonの利用を確認し、/mcp で
# agentcore-cognitoを選んで認証する。認証後にhello_worldを呼び出す。
# Claude Code終了後、再ログインだけ行う場合:
# claude mcp login agentcore-cognito
cd ..

# ローカル確認（任意）。サーバーを別ターミナルで起動する。
# uv run --frozen python server.py
# uv run --frozen python scripts/client.py --local

# 片付け: 呼び出しを終了し、CodexのOAuth認証情報も削除する。
# Claude Codeを使った場合:
# cd claude-code
# claude mcp logout agentcore-cognito
# cd ..
# cd codex
# codex mcp logout agentcore-cognito
# cd ..
# terraform -chdir=terraform plan -destroy '-out=destroy.tfplan'
# 保存した削除プランを適用し、Runtimeが自動作成したロググループも削除する。
# uv run --frozen python scripts/cleanup.py --apply
# terraform -chdir=terraform state list
