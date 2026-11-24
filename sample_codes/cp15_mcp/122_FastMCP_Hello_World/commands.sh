# このファイルのあるディレクトリで順に実行する。
# WindowsのPowerShellでも同じコマンドを1行ずつ実行できる。
uv sync
uv run --frozen python server.py

# サーバーが起動したら、このターミナルを開いたままエージェントから接続する。
# 停止するときは、このターミナルでCtrl+Cを押す。
