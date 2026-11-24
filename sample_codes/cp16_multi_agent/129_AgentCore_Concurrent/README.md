# Concurrent：賃貸物件の比較

費用・通勤・住環境の3担当が独立して評価し、全担当の成功後に統合担当が比較結果をまとめます。

## 構成

```text
Codex / Claude Code → ローカルFastMCP（HTTP）
                              ↓ boto3 / IAM
                       入口・進行役Runtime
                              ↓ A2A / IAM
                         各担当Runtime
```

Pythonクライアントからも同じ入口Runtimeを呼び出せます。ローカルMCPは操作と結果の受け渡しを担当し、各担当の判断と進行制御はAWS上で実行します。

進行役（HTTP）1個と、評価3担当・統合担当（A2A）4個。進行役はasyncio.gatherで並列に呼び、各担当はStrands Agentで処理します。

S3に入力資料・担当別の評価・統合結果を保存します。費用と通勤の計算にはPythonの計算ツールを使います。

## ファイル

| パス | 内容 |
| --- | --- |
| `app/` | AWS上の担当・進行制御・通信・入力検証 |
| `scripts/` | Pythonクライアント、ZIP作成、設定読み取り、片付け |
| `server.py` | ローカルFastMCPのHTTPサーバー |
| `terraform/` | AWSリソースと設定値 |
| `properties/` | 実行時に使う架空のサンプル資料 |
| `codex/.codex/config.toml` | Codexのプロジェクト設定 |
| `claude-code/.mcp.json` | Claude Codeのプロジェクト設定 |
| `commands.sh` | 準備・配置・実行・片付けのコマンド |

## 実行

Python 3.14、uv、Terraform、AWS CLIを用意します。AWSプロファイル・リージョン・モデルの既定値は`terraform/main.tf`にまとめています。既定のプロファイルは`develop`、モデルは`jp.anthropic.claude-sonnet-4-6`です。配置と実行に必要なAWS権限、およびモデルの利用条件を満たしたアカウントを使ってください。

`commands.sh`を上から必要な区間ごとに実行します。WindowsのPowerShellとmacOSのシェルで同じコマンドを使えます。ZIPはLinux ARM64 / Python 3.14向けに作成します。

### コーディングエージェントから接続

ローカルサーバーを起動したターミナルを開いたまま、Codexは`codex/`、Claude Codeは`claude-code/`をプロジェクトとして起動します。設定ファイルの読み込みを許可し、MCPの接続状態とツール一覧を確認してください。接続先は`http://127.0.0.1:8000/mcp`です。同じポートを使うサンプルは一度に1つ起動します。

接続テストではツール一覧に `compare_rentals` があることを確認します。ツール一覧の取得だけではAWSの処理を開始しません。

実行依頼例：

> MCPサーバー `agentcore-concurrent` を使って、サンプルの3物件を比較して、担当別の評価と統合結果を表示して。

ローカルサーバーがAWSプロファイルの認証情報を使い、AWS側ではRuntimeの実行ロールを使います。エージェントには各担当の実際の出力を表示させます。保存された入力や出力は`results/`とAWS側の保存先で確認できます。生成結果は実行ごとに変わります。

処理には数分かかる場合があります。接続が切れた場合は保存済みの状態を確認し、新しい実行をむやみに作らないでください。

統合担当の出力上限は8192トークン、評価担当は2200トークンです。統合に失敗した場合も、保存済みの担当別評価を返します。応答の`status`は`failed`、`summary`は`null`となり、評価の取得に失敗した担当は`report_errors`に記録します。Pythonクライアントの`inspect`でも、既存の実行を再生成せずに完了済み評価を確認できます。

## 片付け

`commands.sh`末尾のコメントアウトされた手順を実行します。削除前にRuntimeのIDを記録し、Terraformで削除した後、自動生成されたログとWorkload Identityを削除します。サンプルのS3内の入力・出力も削除対象です。

## 参考

[Microsoft：AI agent orchestration patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)
