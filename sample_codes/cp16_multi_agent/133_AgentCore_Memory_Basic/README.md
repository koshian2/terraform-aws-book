# AgentCore Memory：会話を保存して再開する

ローカルPythonから会話をAgentCore Memoryへ保存し、Pythonを終了した後も同じセッションの履歴を取得するサンプルです。さらに、取得した履歴をBedrockへ渡して会話を続けます。

```text
Python save ──会話の保存──→ AgentCore Memory
Python history ←──履歴の取得── AgentCore Memory
Python chat ──履歴＋質問──→ Bedrock
            └──質問と回答の保存──→ AgentCore Memory
```

## 構成と準備

| ファイル | 役割 |
|---|---|
| `scripts/client.py` | 保存・履歴取得・履歴を使った回答生成 |
| `terraform/main.tf` | Memory、保持期間、接続先とモデルの設定 |
| `commands.sh` | 準備から片付けまでの実行コマンド |

Python 3.14、uv、Terraform 1.11以上、AWS CLIを使用します。AWSプロファイルは`develop`、リージョンは`ap-northeast-1`、回答モデルは`jp.anthropic.claude-sonnet-4-6`です。設定は`terraform/main.tf`の変数で変更します。Terraform出力をPythonが読み取るため、設定変更後はplan・applyを実行してください。

利用するAWS認証情報にはMemoryの作成・参照・削除・タグ管理、`bedrock-agentcore:CreateEvent`・`ListEvents`、回答モデルと推論プロファイルへの`bedrock:InvokeModel`権限が必要です。

## 実行と確認

実行コマンドは[commands.sh](commands.sh)にまとめています。このサンプル直下で区間ごとに実行してください。WindowsではPowerShellへ各コマンドを貼り付け、macOSではシェルから実行できます。

1. TerraformでMemoryを作成します。
2. `save`で旅行先を保存し、別のPythonプロセスの`history`で同じ本文とevent IDを取得します。未使用のセッションでは`events`が空になります。
3. `chat`で旅行先を省略した質問を送り、履歴を踏まえた回答を確認します。次の質問では前の回答も履歴として渡されます。

`--show-context`はモデルへ渡したメッセージを標準エラーに表示します。回答JSONの`history_event_ids`は参照したイベント、`event_id`は今回保存したイベントです。モデルがMemoryを直接読むのではなく、Pythonが履歴を取得してモデルへ渡しています。

## 保存とセッションの扱い

Memoryは生の会話イベントを7日間保持します。「短期記憶」はPythonの終了とともに消えるという意味ではありません。`actorId`は`alice`、`sessionId`は引数で指定し、同じ組み合わせの履歴を取得します。

`save`と`history`はモデルを呼びません。`chat`は回答後、USERの質問とASSISTANTの回答を1つのイベントに保存します。モデル呼び出しに失敗した場合は新しいイベントを保存せず、回答後の保存に失敗した場合は回答と保存失敗・未確認の状態を表示して終了します。

履歴と質問の合計は30,000文字まで、回答は最大2,048トークンです。`stop_reason`が`max_tokens`なら回答は途中までです。同じセッションは順番に操作してください。手動で保存や質問を再実行すると新しいイベントが増えます。

## 片付け

`commands.sh`末尾のコメントを外して削除計画を確認し、適用します。Memoryと保存した会話が削除されます。
