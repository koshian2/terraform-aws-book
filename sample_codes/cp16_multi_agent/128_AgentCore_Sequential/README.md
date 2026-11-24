# Sequential：商品紹介の制作

商品仕様から訴求整理、紹介文、SNS投稿文を順番に作成します。前の担当エージェントの出力を次の担当エージェントに渡します。

## 構成

```text
Codex / Claude Code → ローカルFastMCP（HTTP）
                              ↓ boto3 / IAM
                       入口・進行役Runtime
                              ↓ A2A / IAM
                         各担当Runtime
```

Pythonクライアントからも同じ入口Runtimeを呼び出せます。ローカルMCPは操作と結果の受け渡しを担当し、各担当エージェントの判断と進行制御はAWS上で実行します。

進行役（HTTP）1つと、訴求整理・紹介文・SNSの各担当エージェント（A2A）3つで構成されます。進行役は固定順序を制御し、各担当エージェントがConverseで文章を生成します。

S3に商品仕様・各工程の入出力・実行記録を保存します。

## ファイル

| パス | 内容 |
| --- | --- |
| `app/` | AWS上の各担当エージェント・進行制御・通信・入力検証 |
| `scripts/` | Pythonクライアント、ZIP作成、設定読み取り、後片付け |
| `server.py` | ローカルFastMCPのHTTPサーバー |
| `terraform/` | AWSリソースと設定値 |
| `product.json` | 実行時に使う架空のサンプル資料 |
| `codex/.codex/config.toml` | Codexのプロジェクト設定 |
| `claude-code/.mcp.json` | Claude Codeのプロジェクト設定 |
| `commands.sh` | 準備・デプロイ・実行・後片付けのコマンド |

## 実行

Python 3.14、uv、Terraform、AWS CLIを用意します。AWSプロファイル・リージョン・モデルの既定値は`terraform/main.tf`にまとめています。既定のプロファイルは`develop`、モデルは`jp.anthropic.claude-sonnet-4-6`です。デプロイと実行に必要なAWS権限、およびモデルの利用条件を満たしたアカウントを使ってください。

`commands.sh`を上から必要なセクションごとに実行します。WindowsのPowerShellとmacOSのシェルで同じコマンドを使えます。ZIPはLinux ARM64 / Python 3.14向けに作成します。

### コーディングエージェントから接続

ローカルサーバーを起動したターミナルを開いたまま、Codexは`codex/`、Claude Codeは`claude-code/`をプロジェクトとして起動します。設定ファイルの読み込みを許可し、MCPの接続状態とツール一覧を確認してください。接続先は`http://127.0.0.1:8000/mcp`です。同じポートを使うサンプルは一度に1つ起動します。

接続テストではツール一覧に `create_product_copy` があることを確認します。ツール一覧の取得だけではAWSの処理を開始しません。

実行依頼例：

> MCPサーバー agentcore-sequential の create_product_copy を、product_file="product.json" で呼び出してください。返された訴求整理・紹介文・SNS投稿文を順番に表示してください。ツールが利用できない場合は、その状態を報告してください。

ローカルサーバーがAWSプロファイルの認証情報を使い、AWS側ではRuntimeの実行ロールを使います。エージェントには、各担当エージェントの実際の出力を表示させます。保存された入力や出力は`results/`とAWS側の保存先で確認できます。生成結果は実行ごとに変わります。

処理には数分かかる場合があります。接続が切れた場合は保存済みの状態を確認し、新しい実行をむやみに開始しないでください。

## 後片付け

`commands.sh`末尾のコメントアウトされた手順を実行します。削除前にRuntimeのIDを記録し、Terraformで削除した後、自動生成されたログとWorkload Identityを削除します。サンプルのS3内の入力・出力も削除対象です。

## 参考

[Microsoft：AI agent orchestration patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)
