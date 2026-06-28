#!/bin/bash
#
# AWS SSM経由でSSHセッションを開始するためのプロキシスクリプトです。 / Proxy script for starting an SSH session through AWS SSM.
# VSCodeのRemote-SSHなどで利用することを想定しています。 / Assumes use with VS Code Remote-SSH or similar tools.
#
# ■ 使用方法 / Usage.
#   $1: AWSプロファイル (例: develop, production など) / AWS profile.
#   $2: 接続先ホスト文字列。 "プロファイル名::インスタンスID" または "インスタンスID" の形式。 / Target host string. Use either profile-name::instance-id or instance-id.
#   $3: ポート番号 (通常は22) / Port number, usually 22.
#
# ■ 注意事項 / Notes
# VSCode Remote-SSHのProxyCommandとして設定する場合、スクリプトは非対話的に実行されます。 / When this is set as the VS Code Remote-SSH ProxyCommand, the script runs non-interactively.
# そのため、SSO認証が必要な場合は、接続前に手動でログインを済ませておく必要があります。 / If SSO authentication is required, log in manually before connecting.
# 認証に失敗した場合、ログインを促すエラーメッセージが表示されます。 / If authentication fails, an error message prompts the user to log in.
#
# 事前ログインコマンド（SSOが必要な場合）: / Pre-login command when SSO is required.
#   aws sso login --profile <プロファイル名> / profile name.
#

# スクリプトを安全に実行するための設定 (エラー発生時に即時終了) / Settings for safe script execution. Exit immediately when an error occurs.
set -euo pipefail

# --- 引数の検証 --- / Validate arguments.
if [ "$#" -ne 3 ]; then
  # 引数が3つでない場合は使い方を標準エラー出力に表示して終了 / If there are not exactly three arguments, show usage on standard error and exit.
  echo "使い方: $0 <aws_profile> <host_string> <port> / Usage: $0 <aws_profile> <host_string> <port>" >&2
  exit 1
fi

# --- 変数の設定 --- / Variable settings
aws_profile="$1"
host_string="$2"
port_number="$3"

# ホスト文字列からインスタンスIDを抽出します。 / Extract the instance ID from the host string.
# "profile::i-12345" のような形式を考慮し、"::" 以降をIDとして取得します。 / For formats like "profile::i-12345", use the part after :: as the ID.
if [[ "$host_string" == *"::"* ]]; then
  instance_id="${host_string##*::}"
else
  instance_id="$host_string"
fi

# --- 接続情報の表示 --- / Show connection information.
# ログが見やすいように接続情報を標準エラー出力に表示します。 / Print connection information to standard error so logs are easy to read.
printf "\n================================================================\n" >&2
printf "AWS SSMプロキシ経由で接続します / Connecting through the AWS SSM proxy\n" >&2
printf "  - AWSプロファイル / AWS profile: %s\n" "$aws_profile" >&2
printf "  - インスタンスID / Instance ID:  %s\n" "$instance_id" >&2
printf "  - ポート番号 / Port number:      %s\n" "$port_number" >&2
printf "================================================================\n\n" >&2

# --- AWS認証情報の検証 --- / Validate AWS credentials.
# `get-caller-identity` を使い、指定したプロファイルの認証情報が有効か確認します。 / Use get-caller-identity to check that credentials for the specified profile are valid.
# 出力は不要なため、/dev/nullにリダイレクトします。 / Redirect output to /dev/null because it is not needed.
if ! aws sts get-caller-identity --profile "$aws_profile" > /dev/null 2>&1; then
  # 認証失敗時のエラーメッセージ / Error message on authentication failure.
  printf "\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n" >&2
  printf "エラー: プロファイル '%s' のAWS認証情報が無効か期限切れです。 / Error: AWS credentials for profile '%s' are invalid or expired.\n" "$aws_profile" "$aws_profile" >&2
  printf "以下のコマンドを実行してSSOログインしてから、再試行してください。 / Run the following command to log in with SSO, then try again.\n\n" >&2
  printf "  aws sso login --profile %s\n" "$aws_profile" >&2
  printf "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n\n" >&2
  exit 1
fi

# --- SSMセッションの開始 --- / Start the SSM session.
# AWS-StartSSHSessionドキュメントを使い、指定したポートでSSHセッションを開始します。 / Use the AWS-StartSSHSession document to start an SSH session on the specified port.
exec aws ssm start-session \
  --target "$instance_id" \
  --document-name AWS-StartSSHSession \
  --parameters "portNumber=${port_number}" \
  --profile "$aws_profile"
