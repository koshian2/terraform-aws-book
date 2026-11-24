#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Windows: WSLのUbuntu等で実行。macOS: ターミナルで実行。
case "$(uname -s)" in
  Linux|Darwin) ;;
  *) echo 'WindowsではGit BashではなくWSLから実行してください。' >&2; exit 1 ;;
esac
docker compose version
docker info >/dev/null
mkdir -p results
docker compose up -d --wait db
docker compose build verify
# WSL/macOSのユーザーと同じ所有者で結果ファイルを保存する。
docker compose run --rm --user "$(id -u):$(id -g)" verify

# 停止（データを残す）:
# docker compose stop db

# 片付け（このサンプルのコンテナ・ネットワーク・DBデータを削除）:
# docker compose --profile verify down --volumes --rmi local

# 初期化SQLを変更した場合は、上の片付けを実行してから再実行する。
