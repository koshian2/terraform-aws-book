# Cognito認証でAgentCoreのMCPを呼び出す

Cognitoでログインして取得したアクセストークンを使い、AgentCore Runtime上の `hello_world` ツールを呼び出します。戻り値は `Hello World` です。Python 3.14とFastMCP 4.1を使います。

```text
ログイン: Python / Codex / Claude Code → Cognitoのログイン画面 → 認可コード＋PKCE → アクセストークン
呼び出し: Python / Codex / Claude Code → HTTPS＋Bearerトークン → AgentCore Runtime → hello_world
```

[123番](../123_AgentCore_MCP_Hello_World/README.md)はIAM署名、[124番](../124_Cognito_Web_Login/README.md)はCognitoのJWTの確認を扱います。このサンプルではJWTをMCPの呼び出しに使います。Runtimeが署名・発行元・期限・`client_id` と `hello-mcp/invoke` scopeを検証します。IDトークンではなくアクセストークンを送信します（詳細は[AgentCoreのJWT認証](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-oauth.html)を参照）。

## 構成

```text
125_AgentCore_MCP_Cognito/
├── server.py                 # Hello Worldツール
├── pyproject.toml
├── commands.sh
├── scripts/
│   ├── build.py              # Linux ARM64用ZIP作成
│   ├── common.py             # Terraformの公開設定を読む
│   ├── create_user.py        # Cognitoユーザー作成
│   ├── login.py              # 認可コード＋PKCE
│   ├── client.py             # ログインしてMCPを呼ぶ
│   ├── configure_codex.py    # Codex設定の生成
│   ├── configure_claude.py   # Claude Code設定の生成
│   └── cleanup.py            # リソースと自動生成ログの削除
├── terraform/                # S3・IAM・Runtime・Cognito
├── codex/.codex/config.toml.example
└── claude-code/.mcp.json.example
```

`server.py` は `0.0.0.0:8000/mcp` で待ち受け、ステートレスなStreamable HTTPで動作します。認証はRuntimeの入口で処理します。ローカルで起動したサーバーには認証がないため、信頼できるネットワークで確認してください。

## 準備とデプロイ

Python 3.14、uv、Terraform 1.12以上2.0未満、AWS CLI v2を用意します。Codex連携には、事前登録OAuthクライアントの設定に対応したCodexが必要です。

AWSプロファイルは `develop`、リージョンは `ap-northeast-1` が既定です。変更は `terraform/terraform.tfvars` で行えます。複数の環境を同じリージョンにデプロイするときは `name` を変更してください。PythonはTerraform出力から接続先を読むため、ARNの転記は不要です。

デプロイにはS3・IAM・AgentCore Runtime・Cognitoの管理権限と実行ロールへの `iam:PassRole` が必要です。ユーザー作成には `cognito-idp:AdminCreateUser` と `cognito-idp:AdminSetUserPassword`、リソースの削除には `logs:DeleteLogGroup` も必要です。初回にサービス連携ロールの作成が必要な場合は `iam:CreateServiceLinkedRole` が必要です。

サンプルのルートで [commands.sh](commands.sh) を上から必要な箇所まで実行します。Windows PowerShellとmacOSで同じコマンドを使えます。ZIPを先に作成し、Terraformがそのハッシュを使ってS3にアップロードします。ソースや依存パッケージを変更した場合は、ZIPの再作成後にplan・applyを実行してください。

ユーザー `reader` のパスワードは非表示の対話入力です。12文字以上で英大文字・英小文字・数字・記号を含めます。パスワードはステートに含めません。既存ユーザーは上書きしません。

## Pythonで確認する

commands.shのクライアント実行で、ブラウザにCognitoのログイン画面が開きます。`reader` でログインすると `http://localhost:8765/callback` に認可コードが返ります。Pythonがstateを検証し、コードとPKCE verifierをトークンに交換してMCPを呼び出します。

```text
Tools: hello_world
Hello World
```

ブラウザとPythonは同じPCで動かします。コールバック待ちは最大5分です。ポート8765が使用中なら、そのプロセスを停止してから実行してください。トークンはプロセスのメモリに保持し、標準出力やファイルには保存しません。Pythonは実行するたびにログインします。

ログイン中だけローカルHTTPで認可コードを受け取ります。MCP通信はRuntimeに直接送信します。終了時はHTTP接続を閉じ、MCPのDELETEを送らずRuntimeのアイドルタイムアウト（60秒）に任せます。

## Codexから直接接続する

`configure_codex.py` がTerraformの出力から `codex/.codex/config.toml` を生成します。`codex/` をプロジェクトとして開いて信頼を確認し、commands.shのログイン手順を実行してください。設定にはURL・クライアントID・scopeだけを含め、CodexがOAuthトークンを自身の認証情報ストアで管理します。

初回ログインでCognitoがredirect_uriを拒否する場合は、次を行います。

1. Codexが表示した認可URLの `redirect_uri` をURLデコードし、実際のコールバックを確認します。ログイン処理はいったんCtrl+Cで終了します。
2. `terraform/terraform.tfvars` に `codex_oauth_callback_url = "http://localhost:8766/callback/<表示されたID>"` を設定します。IDを推測したり、別環境の値をコピーしないでください。
3. commands.shの更新手順でplan・applyを行い、`configure_codex.py --overwrite` で設定を更新します。
4. `codex/` で再ログインします。`/mcp` で `agentcore-cognito` を確認してください。

Codexは認可サーバーのissuer識別対応などに応じて、コールバックURLにサーバー固有IDを付けます。設定の `callback_url` には実際の値を指定します。想定と異なるホストやポートの場合は、そのまま登録せずCodexの設定と表示値を確認してください（詳細は[CodexのOAuth設定](https://learn.chatgpt.com/docs/config-file/config-reference)を参照）。

接続後の依頼例:

> agentcore-cognitoのhello_worldツールを呼び出し、返された文字列だけを表示してください。呼び出せなければ、その旨を伝えてください。

ツール実行履歴と `Hello World` の応答を確認します。PythonでのログインとCodexでのログインは別セッションです。

## Claude Codeから直接接続する

commands.shのClaude Code用手順を実行します。既存環境では、先にTerraformのplan・applyを行い、コールバックURLを追加してください。`configure_claude.py` がTerraform出力から `claude-code/.mcp.json` を生成します。再生成には `--overwrite` を指定します。

`claude-code/` をプロジェクトのルートとしてClaude Codeを起動し、プロジェクトとMCP設定の利用を確認します。`/mcp` から `agentcore-cognito` を選択して認証し、Cognitoで既存の `reader` と同じパスワードを使ってログインします。接続後は上の依頼例で `hello_world` を呼び出してください。再ログインとログアウトのコマンドもcommands.shにあります。

Claude Codeは既存の公開アプリクライアントを使い、アクセストークンを取得してRuntimeに直接接続します。設定には `oauth.clientId`、`callbackPort`（8767）、`scopes`（`openid hello-mcp/invoke`）を指定します。CognitoのOIDCメタデータURLも明示します。パスワード・クライアントシークレット・トークンは設定ファイルに記載しません（詳細は[Claude CodeのOAuth設定](https://code.claude.com/docs/en/mcp#use-pre-configured-oauth-credentials)を参照）。

コールバックURLは `http://localhost:8767/callback` です。Codex用の末尾IDは付けません。`redirect_mismatch` が出たら、Terraformへの反映と認可URLの `redirect_uri` を確認します。Claude Code 2.1.229には `127.0.0.1` を送る問題があり、2.1.231で `localhost` に戻っています。2.1.231以降で、`oauth.scopes` に対応したバージョンを利用してください。Python・Codex・Claude Codeのログイン状態はそれぞれ別です。

## 後片付け

commands.sh末尾の手順で使用したCodex・Claude Codeからログアウトし、削除プランを保存して `cleanup.py --apply` を実行します。ユーザープール内のユーザーも削除されます。

RuntimeのロググループはAWSが自動作成します。Terraformによる同名ロググループの作成は行わず、cleanup.pyがRuntimeの削除後に対象ログだけを削除します。ログ削除に失敗した場合は `build/cleanup.json` を残して同じコマンドを再実行してください。ログを含めた削除が完了するまで `build/` とステートを保持します。アカウント共通のサービス連携ロールは対象外です。

再デプロイ時は使用するエージェントの設定を再生成します。利用を終えた場合は、生成された `codex/.codex/config.toml` と `claude-code/.mcp.json` も削除できます。
