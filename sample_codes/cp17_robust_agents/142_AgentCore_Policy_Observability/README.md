# AgentCore Policyの判定をトレースで確認する

足し算の呼び出しをPolicyで許可・拒否し、CloudWatchのトレースから判定と適用ポリシーを確認するサンプルです。LLMは使用しません。実行コマンドは [commands.sh](commands.sh) にまとめています。サンプル直下でセクションごとに実行してください。

## 構成

```text
Python / Codex / Claude Code
  → Cognitoで認証 → AgentCore Gateway（Policy: ENFORCE）
  → AgentCore Runtime（FastMCPのadd）

GatewayのPolicy判定 → X-Ray / Transaction Search → CloudWatch Logs（aws/spans）
```

MCPツールはRuntimeが公開し、Gatewayが認証・認可を担当します。コーディングエージェントもGatewayのリモートMCPにHTTPで直接接続します。Runtimeへの直接呼び出しはGatewayのIAMロール以外を拒否します。

| 呼び出し | 期待する結果 | 判定を決めるポリシー |
| --- | --- | --- |
| `add(1, 2)` | `sum: 3`、ALLOW | `allow_add` |
| `add(101, 2)` | JSON-RPCエラー `-32002`、DENY | `deny_large_a` |

`allow_add`はaddを許可し、`deny_large_a`は引数aが100を超える場合に拒否します。bにはこの制限を設けていません。両方に一致するとforbidが優先されます。Runtimeの足し算コードには100を境界とする判定を入れていません。

この組み合わせでは静的検証の過剰許可・過剰制限の指摘を許容するため、`validation_mode = "IGNORE_ALL_FINDINGS"`を指定します。実行時のPolicyは`ENFORCE`で評価します。

## 前提と準備

- Python 3.14、uv、Terraform 1.12以上2未満、AWS CLIを用意します。FastMCPは4.1.1、AWSプロバイダーは6.66.0に固定しています。
- AWSの`develop`プロファイルで東京リージョンにデプロイします。設定は`terraform/variables.tf`で変更できます。
- 対象アカウント・リージョンのCloudWatchで、Application Signals（APM）→ Transaction search → Enable Transaction Searchから、スパンを構造化ログとして取り込む設定を有効にします。既に有効な場合はその設定を利用します（詳細は[AWSの設定手順](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-configure.html)を参照）。
- デプロイ権限に加え、観測にはCloudWatch Logsのクエリ開始・結果取得・停止権限が必要です。Cognitoのreaderユーザーとは別に、PythonのAWSプロファイルでログを参照します。

Terraformが作成する観測用リソースは、このGatewayのTRACES配信元、XRAY配信先、両者を結ぶ配信設定です。アカウント共通のTransaction Searchと`aws/spans`の保持期間は既存設定を使用します。ログ保存・クエリ等の料金が発生します。

## Pythonでの確認

commands.shのデプロイ、readerユーザー作成、client、observeの順に実行します。パスワードはユーザー作成時に対話入力します。ブラウザでも**reader**でログインしてください。アクセストークンはプロセス内でのみ保持します。

`scripts/client.py`は許可と拒否の2ケースを各1回呼び出し、UTC時刻・trace ID・HTTPステータス・応答を`results/latest-calls.json`に記録します。Policyの拒否はHTTP 200のJSON-RPCエラーとして返る場合があるため、HTTPステータスだけで成功と判断しません。

`scripts/observe.py`はその記録を読み、`aws/spans`から呼び出し時刻付近のスパンを取得します。trace ID、Gateway ID、Policy Engine、ENFORCE、ALLOW/DENY、判定に使われたPolicy IDを照合し、`results/latest-spans.json`に保存します。属性不足や型不一致によるポリシー評価失敗がないことも確認します（詳細は[AWSのPolicy観測データ仕様](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-policy-metrics.html)を参照）。

トレースには到着遅延があります。既定の300秒で両ケースを確認できなければ`incomplete_observation`、終了コード2になります。これは拒否や許可の成功を意味しません。時間を置き、commands.shの観測コマンドだけを再実行してください。ツールを呼び直す必要はありません。保存済みの呼び出しと一致するトレースが引き続き見つからない場合は、Transaction SearchとGatewayの配信設定を確認します。

CloudWatch Logs Insightsでも、ロググループ`aws/spans`を選び、呼び出した時刻を含む範囲で次のクエリを実行できます。Gateway IDはTerraformの出力に合わせて置き換えます。

```sql
fields @timestamp,
 attributes.`aws.agentcore.policy.authorization_decision` as decision,
 attributes.`aws.agentcore.policy.authorization_reason` as reason,
 attributes.`aws.agentcore.policy.determining_policies` as policies,
 traceId
| filter @message like /<Gateway ID>/
| filter name = "AgentCore.Policy.AuthorizeAction"
| sort @timestamp asc
| limit 100
```

スパンの処理ステータスがOKでもPolicyの判定はDENYの場合があります。`authorization_decision`を確認してください。`authorization_reason`は空の場合があり、`determining_policies`と併せて読みます。

## Codex / Claude Codeからの確認

commands.shの設定生成を実行します。Codexは`codex/`、Claude Codeは`claude-code/`で起動してください。configure処理はCognitoのコールバック登録とログイン画面への到達を確認してから設定ファイルを生成します。認証するユーザーはreaderです。

サンプルプロンプト:

> agentcore-policy-observabilityのMCPを使って、1と2の足し算、101と2の足し算をそれぞれ1回ずつ実行してください。成功した結果と拒否された内容を分けて表示し、拒否された計算は再試行しないでください。

コーディングエージェントの呼び出しはPythonの`latest-calls.json`には記録されません。こちらの判定はCloudWatchで時刻とGateway IDを絞って確認します。trace IDによる自動照合はPythonの2ケースが対象です。

## ファイルと後片付け

| 場所 | 役割 |
| --- | --- |
| `app/server.py` | 足し算MCP |
| `terraform/` | Runtime、Gateway、Cognito、Policy、トレース配信 |
| `scripts/client.py`・`transport.py` | 認証後の2ケース実行と通信記録 |
| `scripts/observe.py` | 判定トレースの照合 |
| その他の`scripts/` | ビルド、ユーザー作成、接続設定、後片付け |
| `results/` | ローカル実行記録（Git管理対象外） |

後片付けはcommands.sh末尾のコメントアウトされた手順を使用します。削除前に対象を記録し、Terraformで削除した後、RuntimeのログとRuntime・GatewayのWorkload Identityも削除します。共有のTransaction Search、`aws/spans`、AWSが自動作成する共有のトレース配信用リソースポリシーは残します。
