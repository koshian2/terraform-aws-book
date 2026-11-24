# Handoff：担当者間の引き継ぎ

本棚の相談を前任から後任に引き継ぎます。後任が不足情報を質問し、前任が回答した後に担当を変更します。

## 構成

```text
Codex / Claude Code → ローカルFastMCP（HTTP）
                              ↓ boto3 / IAM
                       入口・進行役Runtime
                              ↓ A2A / IAM
                         各担当Runtime
```

Pythonクライアントからも同じ入口Runtimeを呼び出せます。ローカルMCPは操作と結果の受け渡しを担当し、各担当エージェントの判断と進行制御はAWS上で実行します。

入口（HTTP）1つと、前任・後任の各担当エージェント（A2A）2つで構成されます。入口は保存済みの担当に振り分け、前任と後任のStrands Agentが質疑応答（Q&A）を行います。

DynamoDBに案件状態・前任の記録・後任の受領情報を保存します。確認は最大2往復です。引き継ぎ前後の質問は同じ内容にして、記録の受け渡しを観察します。

## ファイル

| パス | 内容 |
| --- | --- |
| `app/` | AWS上の各担当エージェント・進行制御・通信・入力検証 |
| `scripts/` | Pythonクライアント、ZIP作成、設定読み取り、後片付け |
| `server.py` | ローカルFastMCPのHTTPサーバー |
| `terraform/` | AWSリソースと設定値 |
| `case-notes.md` | 実行時に使う架空のサンプル資料 |
| `codex/.codex/config.toml` | Codexのプロジェクト設定 |
| `claude-code/.mcp.json` | Claude Codeのプロジェクト設定 |
| `commands.sh` | 準備・デプロイ・実行・後片付けのコマンド |

## 実行

Python 3.14、uv、Terraform、AWS CLIを用意します。AWSプロファイル・リージョン・モデルの既定値は`terraform/main.tf`にまとめています。既定のプロファイルは`develop`、モデルは`jp.anthropic.claude-sonnet-4-6`です。デプロイと実行に必要なAWS権限、およびモデルの利用条件を満たしたアカウントを使ってください。

`commands.sh`を上から必要なセクションごとに実行します。WindowsのPowerShellとmacOSのシェルで同じコマンドを使えます。ZIPはLinux ARM64 / Python 3.14向けに作成します。

### コーディングエージェントから接続

ローカルサーバーを起動したターミナルを開いたまま、Codexは`codex/`、Claude Codeは`claude-code/`をプロジェクトとして起動します。設定ファイルの読み込みを許可し、MCPの接続状態とツール一覧を確認してください。接続先は`http://127.0.0.1:8000/mcp`です。同じポートを使うサンプルは一度に1つ起動します。

接続テストではツール一覧に `create_case / ask_current_owner / handoff_case / advance_handoff / get_case_status` があることを確認します。ツール一覧の取得だけではAWSの処理を開始しません。

実行依頼例：

> MCPサーバー `agentcore-handoff` を使って、minimalで案件を作り、前任への質問、後任への引き継ぎ、QA、後任への同じ質問まで順番に進めて。実際の発言と担当の変化を表示して。

ローカルサーバーがAWSプロファイルの認証情報を使い、AWS側ではRuntimeの実行ロールを使います。エージェントには、各担当エージェントの実際の出力を表示させます。保存された入力や出力は`results/`とAWS側の保存先で確認できます。生成結果は実行ごとに変わります。

処理には数分かかる場合があります。接続が切れた場合は保存済みの状態を確認し、新しい実行をむやみに開始しないでください。

## 後片付け

`commands.sh`末尾のコメントアウトされた手順を実行します。削除前にRuntimeのIDを記録し、Terraformで削除した後、自動生成されたログとWorkload Identityを削除します。サンプルのDynamoDB内の案件・QA記録も削除対象です。

## 参考

[Microsoft：AI agent orchestration patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)
