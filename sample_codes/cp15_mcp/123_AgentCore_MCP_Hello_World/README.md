# AgentCore RuntimeでHello Worldを返すMCPサーバー

[122番](../122_FastMCP_Hello_World/README.md)と同じ `hello_world` ツールをAmazon Bedrock AgentCore Runtimeで動かします。戻り値は `Hello World` です。サーバーでLLMは使いません。

Python 3.14・FastMCP 4.1を使用します。Linux ARM64用の依存パッケージをZIPにまとめ、TerraformでS3・IAM実行ロール・AgentCore Runtime・CloudWatch Logsを作成します。Dockerは不要です。

## 接続の構成

```text
コーディングエージェント
  → HTTP http://127.0.0.1:8001/mcp
  → ローカルのproxy.py（AWS認証情報でSigV4署名）
  → HTTPS / AgentCore Runtime
  → server.py :8000/mcp → hello_world() → "Hello World"
```

AgentCoreの接続先はIAM認証を使うため、エージェントにAWS側のURLを設定するだけでは接続できません。手元で起動する `proxy.py` が署名を担当します。ツール一覧と実行結果はAWS側から中継されます。認証情報をエージェントの設定ファイルに書く必要はありません。

プロキシは `127.0.0.1` で待ち受けます。エージェントとプロキシは同じマシン・ネットワーク環境で動かしてください。同じPCのプロセスはプロキシを通してAWSのツールを呼び出せるため、利用終了後はプロキシを停止します。

## ファイル構成

```text
123_AgentCore_MCP_Hello_World/
├── server.py                 # AWSにデプロイするHello Worldツール
├── pyproject.toml
├── commands.sh               # 準備・デプロイ・接続確認・削除
├── scripts/
│   ├── build.py              # Linux ARM64用ZIPの作成
│   ├── connection.py         # Terraform出力の取得・IAM署名
│   ├── client.py             # ツール一覧とHello Worldの確認
│   └── proxy.py              # エージェント向けのHTTP中継
├── terraform/                # S3・IAM・Runtime・ログの定義
├── codex/.codex/config.toml
├── claude-code/.mcp.json
├── antigravity/.agents/mcp_config.json
└── kiro/.kiro/settings/mcp.json
```

`build/hello-world.zip` はビルド時に生成されます。ZIPに入れる本体コードは `server.py` だけです。署名用のboto3など、手元で使う依存パッケージはdevグループに分けています。

## 準備とデプロイ

必要なものはPython 3.14、uv、Terraform 1.12以上2.0未満、AWS CLI v2です。それぞれを実行するターミナルのPATHから利用できるようにしてください。

AWSプロファイルの既定値は `develop`、リージョンは `ap-northeast-1` です。変更する場合は `terraform/variables.tf` の値を変更するか、`terraform/terraform.tfvars` で上書きします。クライアントスクリプトはTerraformの出力からプロファイル・リージョン・URLを読み込むため、コードへのARNの転記は不要です。プロファイルを変更した場合はログイン先も合わせます。

デプロイ実行者にはS3・IAM・AgentCore Runtime・CloudWatch Logsの管理権限と、実行ロールへの `iam:PassRole` が必要です。初回にサービス連携ロールの作成が必要なアカウントでは `iam:CreateServiceLinkedRole` も必要です。呼び出し元には対象Runtimeの `bedrock-agentcore:InvokeAgentRuntime` 権限を付与します。`invoke_policy_json` 出力はそのポリシー例です。出力だけでは権限は付与されません。

サンプルのルートで [commands.sh](commands.sh) の1〜4を順に実行します。WindowsではPowerShellにコマンドを1行ずつ貼り付けられます。macOSも同じコマンドです。このファイルは複数ターミナルでの操作を含む手順集なので、一括実行しないでください。

ZIPの作成を先に行い、Terraformが内容のハッシュを計算してS3にアップロードします。ソースや依存パッケージを変更した場合は、再ビルドしてからplan・applyを実行します。保存したplanの作成後にZIPを変更した場合は、planも作り直してください。複数のサンプル環境を同じアカウント・リージョンにデプロイする場合は `name` を変更します。

## エージェントから接続する

commands.shの5でHTTPプロキシを起動してターミナルを開いたままにし、別ターミナルで6を実行します。次の結果が得られたら、使用するエージェントのフォルダをプロジェクトとして開きます。

```text
Tools: hello_world
Hello World
```

| エージェント | 開くフォルダ | 配置済みの設定 |
|---|---|---|
| Codex | `codex/` | [.codex/config.toml](codex/.codex/config.toml) |
| Claude Code | `claude-code/` | [.mcp.json](claude-code/.mcp.json) |
| Antigravity | `antigravity/` | [.agents/mcp_config.json](antigravity/.agents/mcp_config.json) |
| Kiro | `kiro/` | [.kiro/settings/mcp.json](kiro/.kiro/settings/mcp.json) |

設定を再読み込みし、MCP一覧で `agentcore-hello-world` を確認します。登録操作の詳細は [121番](../121_AWS_Knowledge_MCP/README.md) を参照してください。次の依頼でツールの実行履歴と結果を確認します。

> agentcore-hello-worldのhello_worldツールを呼び出し、返された文字列だけを表示してください。呼び出せなければ、その旨を伝えてください。

期待値は `Hello World` です。文章を生成しただけでは接続確認にならないので、ツールの実行履歴も確認します。

## 実装上の要点

AgentCore上のサーバーは `0.0.0.0:8000/mcp` で待ち受け、`stateless_http=True` でプラットフォームのセッションIDを受け取ります。手元でこのサーバーを起動するときも全インターフェースで待ち受けるため、ローカル確認は信頼できるネットワークで行ってください。

クライアントスクリプトは `mode="legacy"` を指定し、MCPの初期化ハンドシェイクを使います。プロキシは操作ごとにAWS側への接続を作成し、アイドルタイムアウトしたセッションを再利用しません。Runtimeのアイドルタイムアウトは60秒、最大セッション有効時間は600秒です。

AgentCoreへの接続では `terminate_on_close=False` を指定し、終了時のMCPセッション削除（HTTP DELETE）を送信しません。手元のHTTP接続は閉じ、AWS側の実行セッションはアイドルタイムアウトで終了させます。この処理は直接呼び出しとプロキシ経由で共通です。

## 接続できないときと後片付け

接続できない場合は、まず直接呼び出し、プロキシ経由の呼び出し、エージェントの順で確認します。認証期限切れならAWSに再ログインし、403の場合は呼び出し元の権限を確認してください。Terraform出力を取得できない場合は、デプロイが完了しているか、`terraform/terraform.tfstate` があるかを確認します。

終了時はプロキシとローカルサーバーをCtrl+Cで停止します。AWSリソースはcommands.sh末尾の削除手順で削除します。TerraformはコードZIP、S3バケット、実行ロール、Runtime、7日保持のロググループを管理します。ステートは削除が完了するまで保持してください。アカウント共通のサービス連携ロールは管理対象外です。エージェントの登録も外す場合は、設定ファイルから `agentcore-hello-world` を削除します。

## 参考

- [AgentCoreのMCP要件](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-mcp-protocol-contract.html)
- [Python ZIPデプロイ](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-get-started-code-deploy-python.html)
- [AgentCoreの対応ランタイム](https://docs.aws.amazon.com/bedrock-agentcore-control/latest/APIReference/API_CodeConfiguration.html)
- [FastMCPのプロキシ](https://gofastmcp.com/servers/providers/proxy)
- [Terraform AWS Provider 6.66.0のRuntime定義](https://github.com/hashicorp/terraform-provider-aws/blob/v6.66.0/website/docs/r/bedrockagentcore_agent_runtime.html.markdown)
