# インストールの確認
uv --version

# Python本体のインストールとバージョン管理
uv python install 3.14

# プロジェクトの作成
uv init hello-python
cd hello-python

# プログラムの実行
uv run python -c "print('Hello, Python!')"

# パッケージの追加
uv add requests

# パッケージの追加
uv run python -c "import requests"

# 配布されたプロジェクトの環境再現
uv sync
