#!/bin/bash
#
# AWS SSM経由でSSHセッションを開始するためのプロキシスクリプトです。
# VSCodeのRemote-SSHなどで利用することを想定しています。
#
# ■ 使用方法
#   $1: AWSプロファイル (例: develop, production など)
#   $2: 接続先ホスト文字列。 "プロファイル名::インスタンスID" または "インスタンスID" の形式。
#   $3: ポート番号 (通常は22)
#
# ■ 注意事項
# VSCode Remote-SSHのProxyCommandとして設定する場合、スクリプトは非対話的に実行されます。
# そのため、SSO認証が必要な場合は、接続前に手動でログインを済ませておく必要があります。
# 認証に失敗した場合、ログインを促すエラーメッセージが表示されます。
#
# 事前ログインコマンド（SSOが必要な場合）:
#   aws sso login --profile <プロファイル名>
#

# スクリプトを安全に実行するための設定 (エラー発生時に即時終了)
set -euo pipefail

# --- 引数の検証 ---
if [ "$#" -ne 3 ]; then
  # 引数が3つでない場合は使い方を標準エラー出力に表示して終了
  echo "使い方: $0 <aws_profile> <host_string> <port>" >&2
  exit 1
fi

# --- 変数の設定 ---
aws_profile="$1"
host_string="$2"
port_number="$3"

# ホスト文字列からインスタンスIDを抽出します。
# "profile::i-12345" のような形式を考慮し、"::" 以降をIDとして取得します。
if [[ "$host_string" == *"::"* ]]; then
  instance_id="${host_string##*::}"
else
  instance_id="$host_string"
fi

# --- 接続情報の表示 ---
# ログが見やすいように接続情報を標準エラー出力に表示します。
printf "\n================================================================\n" >&2
printf "AWS SSMプロキシ経由で接続します\n" >&2
printf "  - AWSプロファイル: %s\n" "$aws_profile" >&2
printf "  - インスタンスID:  %s\n" "$instance_id" >&2
printf "  - ポート番号:      %s\n" "$port_number" >&2
printf "================================================================\n\n" >&2

# --- AWS認証情報の検証 ---
# `get-caller-identity` を使い、指定したプロファイルの認証情報が有効か確認します。
# 出力は不要なため、/dev/nullにリダイレクトします。
if ! aws sts get-caller-identity --profile "$aws_profile" > /dev/null 2>&1; then
  # 認証失敗時のエラーメッセージ
  printf "\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n" >&2
  printf "エラー: プロファイル '%s' のAWS認証情報が無効か期限切れです。\n" "$aws_profile" >&2
  printf "以下のコマンドを実行してSSOログインしてから、再試行してください。\n\n" >&2
  printf "  aws sso login --profile %s\n" "$aws_profile" >&2
  printf "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n\n" >&2
  exit 1
fi

# --- SSMセッションの開始 ---
# AWS-StartSSHSessionドキュメントを使い、指定したポートでSSHセッションを開始します。
exec aws ssm start-session \
  --target "$instance_id" \
  --document-name AWS-StartSSHSession \
  --parameters "portNumber=${port_number}" \
  --profile "$aws_profile"