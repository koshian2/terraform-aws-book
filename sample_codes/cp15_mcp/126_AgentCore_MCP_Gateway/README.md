# AgentCore GatewayでMCPとLambdaをまとめる

1つのAgentCore Gatewayに、Hello World MCP、AWS Knowledge MCP、足し算用Lambdaを登録します。Codex・Claude Code・PythonはGatewayのURLだけに接続し、3つの接続先のツールを呼び出せます。

```text
Python / Codex / Claude Code
    │ Cognitoでログイン → アクセストークン
    ▼
AgentCore Gateway（JWT認証）
    ├─ IAM署名 → AgentCore Runtime → Hello World MCP
    ├─ HTTPS   → AWS Knowledge MCP（公開サーバー）
    └─ IAM権限 → Lambda → 2つの数値を足す
```

Gatewayは既存MCPのツールを集約するとともに、MCP未対応のLambdaもツールとして公開します。LambdaにはFastMCPは不要です。Gatewayはモデルを動かしたり、質問からツールを選んだりしません。選択はコーディングエージェントが行い、Pythonの確認コードでは呼び出す順序を指定しています。[Gatewayの基本概念](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-core-concepts.html)

## 接続先とツール

| ターゲット名 | 接続先 | 呼び出すツール | 確認結果 |
| --- | --- | --- | --- |
| `hello-runtime` | Runtime上のFastMCP | `hello-runtime___hello_world` | `Hello World` |
| `aws` | AWS Knowledge MCP | `aws___aws___search_documentation` など | AWS公式ドキュメントの検索結果 |
| `calculator` | Lambda関数 | `calculator___add` | `a=12, b=30` で `{"result":42}` |

Gatewayはターゲット名と元のツール名を `___` でつなぎます。AWS側のツールにも接頭辞があるため重複して見える場合があります。公開MCPのツールは更新される可能性があるため、実際の一覧を確認してください。PythonはAWS検索ツールを一覧から選びます。[ツールの命名](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-tool-naming.html)

Lambdaの入力スキーマは `terraform/calculator.tf` に定義します。Gatewayは入力引数をLambdaの `event` 直下へ渡し、Lambdaが返すJSONをMCPの応答に変換します。公開するLambdaツールは `add` の1つです。[Lambdaターゲット](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-add-target-lambda.html)

## ファイル構成

```text
126_AgentCore_MCP_Gateway/
├── server.py                 # Hello World MCP
├── calculator/handler.py     # 足し算用Lambda
├── pyproject.toml
├── commands.sh               # 準備・配置・接続・片付け
├── terraform/
│   ├── main.tf               # Runtime・コード用S3
│   ├── gateway.tf            # Gateway・MCPターゲット・呼び出し権限
│   ├── calculator.tf         # Lambda・ツール定義・ログ
│   ├── cognito.tf            # ログイン用ユーザープール
│   ├── iam.tf                # Runtime実行ロール
│   ├── providers.tf
│   ├── variables.tf
│   └── outputs.tf
├── scripts/
│   ├── build.py              # Runtime用とLambda用のZIP作成
│   ├── common.py             # Terraform出力の読み込み
│   ├── create_user.py        # ユーザー作成
│   ├── login.py              # 認可コード＋PKCE
│   ├── client.py             # Gatewayの一覧・3種類の呼び出し
│   ├── configure_codex.py
│   ├── configure_claude.py
│   └── cleanup.py            # 削除プラン適用・Runtimeログの削除
├── codex/.codex/config.toml.example
└── claude-code/.mcp.json.example
```

## 準備と配置

Python 3.14、uv、Terraform 1.12以上2.0未満、AWS CLI v2を使用します。AWS Providerは6.66.0を使用します。AWSプロファイルは `develop`、リージョンは `ap-northeast-1` です。変更は `terraform/terraform.tfvars` で指定します。同じリージョンに複数配置する場合は `name` を変えてください。

[commands.sh](commands.sh) の必要なブロックを順に実行します。Windows PowerShellとmacOSで共通です。対話操作があるため、一括実行はしません。ZIPを先に作り、Terraformで配置します。ソース変更後もZIPの再作成とplan・applyが必要です。`server.py` はLinux ARM64のRuntime、LambdaはPython 3.14・ARM64で動作します。

デプロイにはS3・IAM・AgentCore Runtime/Gateway・Cognito・Lambda・CloudWatch Logsの管理権限と `iam:PassRole` が必要です。初回はサービス連携ロールを作る権限が必要な場合もあります。Pythonでのユーザー作成には `cognito-idp:AdminCreateUser` と `cognito-idp:AdminSetUserPassword` を使います。

このサンプル専用のCognitoに `reader` を作成します。パスワードは対話入力で、12文字以上・英大文字・英小文字・数字・記号を含めます。他のサンプルのユーザープールとは別です。

Gatewayが利用者のJWTを検証し、RuntimeとLambdaはGatewayのIAMロールで呼び出します。RuntimeのリソースポリシーはGatewayロール以外の直接呼び出しを拒否します。AWS Knowledge MCPへの送信は認証不要です。利用者のCognitoトークンを接続先へ転送する構成ではありません。

## Pythonで確認する

commands.shのクライアント実行でCognitoへログインすると、ツール一覧、Hello World、Lambdaの足し算、AWSドキュメント検索を順に確認できます。`--query` で検索語を指定できます。結果はツールの生の応答で、回答生成用LLMは呼び出しません。トークンはメモリ内に保持します。

ローカル確認の `--local` はHello World MCPだけを呼びます。Gatewayによる集約とLambda実行はAWS配置後に確認してください。ログイン時はPythonがポート8765でコールバックを受けるため、ブラウザとPythonを同じPCで動かします。

## Codex・Claude Codeから接続する

commands.shの設定生成を実行すると、Terraformの出力から次のファイルを生成します。URL・クライアントIDなどの公開設定だけを含み、パスワードやトークンは含めません。

| クライアント | 開くフォルダ | 生成ファイル | コールバック |
| --- | --- | --- | --- |
| Codex | `codex/` | `.codex/config.toml` | ポート8766 |
| Claude Code | `claude-code/` | `.mcp.json` | `http://localhost:8767/callback` |

それぞれのフォルダで起動し、プロジェクトとMCP設定の利用を確認します。MCP名は `agentcore-gateway` です。Claude Codeは `/mcp` から対象を選んで認証します。CLIによる再ログインもcommands.shに記載しています。公開クライアントID・固定コールバックポート・scope指定に対応した版を使ってください。[Claude CodeのOAuth設定](https://code.claude.com/docs/en/mcp#use-pre-configured-oauth-credentials)

Codexの初回認証で `redirect_mismatch` が出た場合は、認可URLの `redirect_uri` を確認します。ID付きのパスが表示されたら、ログインをCtrl+Cで終了し、`terraform/terraform.tfvars` に `codex_oauth_callback_url = "http://localhost:8766/callback/<表示されたID>"` を設定します。ホストは `localhost` に揃えます。commands.shの更新ブロックでplan・apply・Codex設定の再生成を行い、新しい認可URLでログインします。以前のサンプルのIDは使い回しません。[CodexのOAuth設定](https://learn.chatgpt.com/docs/config-file/config-reference)

接続後は次のように依頼します。

- 「agentcore-gatewayのhello-runtime___hello_worldを呼び、結果を表示して」
- 「agentcore-gatewayのcalculator___addで12と30を足して」
- 「agentcore-gatewayのAWS検索ツールでLambdaの最大実行時間を調べ、出典を示して」

各ツールの実行履歴を確認します。Python・Codex・Claude Codeの認証情報はそれぞれ別管理です。

## ターゲット登録に失敗した場合

Gatewayターゲットは登録時に接続先のツールを取得します。登録エラーが出た場合は、IAM権限・Runtimeの起動ログ・外部MCPの到達性を確認してください。単に待てば直るとは限りません。修正後、Terraformのplanで失敗したターゲットの作成・再作成内容を確認してapplyします。

Runtimeのターゲット登録前に、Gatewayの権限とRuntimeのリソースポリシー設定後60秒待機します。権限の反映完了を保証する待ち時間ではありません。

Hello Worldターゲットの初回登録でAuthorization errorが表示された場合は、commands.shの復旧ブロックで対象ターゲットだけを再同期し、AWS上のstatusがREADYになった場合に限りTerraformの失敗フラグを解除してrefresh-onlyプランを適用します。最後の通常planで差分がないことを確認してください。FAILEDのまま失敗フラグを解除しないでください。

## 片付け

commands.sh末尾で使用したクライアントからログアウトし、削除専用プランを保存して `cleanup.py --apply` を実行します。Gateway・ターゲット・Runtime・Lambda・Cognito・S3・専用IAMロール・LambdaログはTerraformで削除します。Runtimeが自動作成するロググループは、Terraformリソースの削除後にスクリプトで削除します。公開AWS Knowledge MCP自体はこのサンプルの管理対象ではありません。

削除途中で失敗した場合はステート・ZIP・`build/cleanup.json` を保持して再試行します。再配置するときはエージェント設定も再生成してください。
