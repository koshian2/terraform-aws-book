# Magentic：修理・保険・代車の計画

ディーラーが窓口を保ち、修理・保険・代車の照会結果を受けて計画を更新します。管理役のLLMが次の照会先・質問・終了を判断します。

## 構成

```text
Codex / Claude Code → ローカルFastMCP（HTTP）
                              ↓ boto3 / IAM
                       入口・進行役Runtime
                              ↓ A2A / IAM
                         各担当Runtime
```

Pythonクライアントからも同じ入口Runtimeを呼び出せます。ローカルMCPは操作と結果の受け渡しを担当し、各担当の判断と進行制御はAWS上で実行します。

管理役（HTTP）1個と、修理・保険・代車の専門家（A2A）3個。管理役と専門家はStrands Agentで処理し、各照会の後に管理役が計画を更新します。

DynamoDBに計画・照会結果・進行番号を保存し、専門家はS3の自分の資料を読みます。照会は最大8回です。normalとdelayedで修理期間の変化と再計画を比較できます。

## ファイル

| パス | 内容 |
| --- | --- |
| `app/` | AWS上の担当・進行制御・通信・入力検証 |
| `scripts/` | Pythonクライアント、ZIP作成、設定読み取り、片付け |
| `server.py` | ローカルFastMCPのHTTPサーバー |
| `terraform/` | AWSリソースと設定値 |
| `fixtures/` | 実行時に使う架空のサンプル資料 |
| `codex/.codex/config.toml` | Codexのプロジェクト設定 |
| `claude-code/.mcp.json` | Claude Codeのプロジェクト設定 |
| `commands.sh` | 準備・配置・実行・片付けのコマンド |

## 実行

Python 3.14、uv、Terraform、AWS CLIを用意します。AWSプロファイル・リージョン・モデルの既定値は`terraform/main.tf`にまとめています。既定のプロファイルは`develop`、モデルは`jp.anthropic.claude-sonnet-4-6`です。配置と実行に必要なAWS権限、およびモデルの利用条件を満たしたアカウントを使ってください。

`commands.sh`を上から必要な区間ごとに実行します。WindowsのPowerShellとmacOSのシェルで同じコマンドを使えます。ZIPはLinux ARM64 / Python 3.14向けに作成します。

### コーディングエージェントから接続

ローカルサーバーを起動したターミナルを開いたまま、Codexは`codex/`、Claude Codeは`claude-code/`をプロジェクトとして起動します。設定ファイルの読み込みを許可し、MCPの接続状態とツール一覧を確認してください。接続先は`http://127.0.0.1:8000/mcp`です。同じポートを使うサンプルは一度に1つ起動します。

接続テストではツール一覧に `create_case / advance_case / get_case_status` があることを確認します。ツール一覧の取得だけではAWSの処理を開始しません。

実行依頼例：

> MCPサーバー `agentcore-magentic` を使って、部品待ちケースを実行して。問い合わせ、専門家の回答、計画変更を表示しながら、完了またはblockedまで進めて。

ローカルサーバーがAWSプロファイルの認証情報を使い、AWS側ではRuntimeの実行ロールを使います。エージェントには各担当の実際の出力を表示させます。保存された入力や出力は`results/`とAWS側の保存先で確認できます。生成結果は実行ごとに変わります。

処理には数分かかる場合があります。接続が切れた場合は保存済みの状態を確認し、新しい実行をむやみに作らないでください。

## 片付け

`commands.sh`末尾のコメントアウトされた手順を実行します。削除前にRuntimeのIDを記録し、Terraformで削除した後、自動生成されたログとWorkload Identityを削除します。サンプルのS3内の入力・出力とDynamoDB内の計画・照会記録も削除対象です。

## 参考

[Microsoft：AI agent orchestration patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)
