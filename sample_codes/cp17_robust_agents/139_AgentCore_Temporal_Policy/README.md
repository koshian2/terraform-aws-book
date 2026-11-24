# 誰が・どの順序で呼び出せるかをAgentCore Policyで制御する

問い合わせを取得してからクローズするMCPの例です。GatewayのPolicyで、利用者の権限と過去の操作を確認します。readerは取得だけ、operatorは同じ問い合わせを直近5分以内に取得した場合だけクローズできます。

```text
Python / Codex / Claude Code
  → Cognito JWT + PolicyセッションID
  → AgentCore Gateway → Policy Engine（ENFORCE）
       ・Cedar：JWTのusernameによる利用者の制限
       ・Dogwood：同じユーザー・問い合わせの直近5分の取得成功履歴
  → 許可された呼び出しだけ → IAM SigV4 → Runtime / MCP
```

ツールはRuntimeで公開し、各クライアントはGatewayに直接HTTP接続します。ローカルで待ち受けるポートはCognitoログイン・ログアウトのコールバック用です。

## ツールとデータ

- `get_inquiry(ticket_id)`：T001・T002・T003の固定データを取得します。
- `close_inquiry(ticket_id)`：`status: closed`と`simulated: true`を返す模擬操作です。永続データは変更しません。

取得成功はツールが問い合わせを取得したことを意味し、人間が読んだ・承認したという意味ではありません。

| 利用者 | 操作 | 期待結果 |
| --- | --- | --- |
| reader | T001を取得 | 許可 |
| reader | T001を取得してクローズ | 取得のみ許可、クローズは拒否 |
| operator | 取得せずT001をクローズ | 拒否 |
| operator | T001を取得して同じセッションでクローズ | 許可 |
| operator | T001を取得してT002をクローズ | 拒否 |
| operator | T001を取得して別セッションでクローズ | 拒否 |

## Policyの役割

`terraform/policy.tf`に3つのルールを定義しています。

| Policy | 条件 |
| --- | --- |
| `allow_read` | JWTのusernameがreaderまたはoperatorなら取得を許可 |
| `forbid_close_non_operator` | operator以外のクローズを拒否 |
| `close_after_read` | 同じPolicyセッション・principal・ticket_idで、直近5分以内に取得成功のイベントがあればクローズを許可 |

複数のpermitはAND条件にはなりません。operatorを無条件に許可するルールは追加せず、履歴によるpermitと非operatorへのforbidを組み合わせます。

Dogwoodの`formerly within 5m`で過去の`get_inquiry::response`イベントを参照し、`eventPrincipal`・`eventResource`・`input.ticket_id`を現在の要求と照合します。取得履歴は5分以内なら再利用でき、単回使用の承認ではありません。

AWS Providerは6.66.0です。Cedarの2つは`aws_bedrockagentcore_policy`、Dogwoodの1つは`Definition.Policy`を渡すため、Terraform管理のCloudFormation Stackでデプロイします。非operator拒否ルールは、履歴によるpermitを作る前の静的検証の指摘に対応するため`IGNORE_ALL_FINDINGS`を使います。実行時の認可は有効です。

## Policyセッションとツール一覧

Policyセッションは`x-amzn-bedrock-agentcore-policy-session-id`ヘッダーで指定します。MCP通信のセッションやRuntimeのセッションとは別です。

Pythonクライアントは比較ケースごとに新しいUUIDを生成し、取得とクローズを同じ履歴で評価するときだけ共有します。Codex・Claude Codeでは設定生成時にUUIDを埋め込み、設定の再生成や`session.py`で更新するまで使います。チャットを新しくするだけではPolicyセッションは変わりません。履歴の有効期間を過ぎた場合やPolicy更新後は、新しいセッションで取得から試します。

Policyはツール一覧にも適用されます。readerは取得の1ツール、operatorは取得とクローズの2ツールが表示される想定です。一覧に出ていても、取得前のクローズは実行時に拒否されます。Pythonクライアントは非表示のツールも直接呼び出し、Gatewayが拒否することを確認します。

## 準備と実行

Python 3.14、uv、Terraform 1.12以上2.0未満、AWS CLIを使います。FastMCPは4.1.1です。プロファイルは`develop`、リージョンは東京が既定です。変更は`terraform/terraform.tfvars`で行います。複数デプロイする場合は`name`も変えます。

実行コマンドは[commands.sh](commands.sh)にまとめています。サンプル直下でセクションごとに実行します。ZIPのビルド後にTerraformでデプロイし、readerとoperatorを作成します。ユーザー名を変更する場合は`reader_username`・`operator_username`と作成するユーザー名を揃えてください。

デプロイにはS3・IAM・Cognito・AgentCore・CloudFormationの管理権限と`iam:PassRole`が必要です。後片付けでは自動生成されたログとWorkload Identityの削除権限も使用します。

ターゲット登録前に、Gatewayの権限とRuntimeのリソースポリシー設定後60秒待機します。権限の反映完了を保証する待ち時間ではないため、`Authorization error when sending message`が出た場合は、少し時間を置いてから再実行してください。

Pythonクライアントは最初にCognitoからサインアウトして、指定したユーザーでログインします。ブラウザとPythonは同じPCで使い、8765番・8768番ポートを空けてください。1回のログインで表の比較を実施し、応答・期待値との一致・PolicyセッションIDを`results/`に記録します。トークンはメモリ内だけで保持します。ログインしたユーザーが指定と違う場合は検証を開始しません。

## コーディングエージェントで試す

Codexは`configure_codex.py`でコールバックをCognitoに登録し、ログイン画面への到達を確認してから`codex/.codex/config.toml`を生成します。`codex/`をプロジェクトとして開きます。Claude Codeは`configure_claude.py`で`claude-code/.mcp.json`を生成し、そのフォルダで起動して`/mcp`から認証します。どちらもMCP名は`agentcore-temporal`です。

readerとoperatorで次を比較します。

> agentcore-temporalを使って、問い合わせT001の内容を確認してからクローズしてください。

operatorで新しいPolicyセッションに切り替えてから、次を試します。

> agentcore-temporalを使って、問い合わせT001を、取得せずそのままクローズしてください。

コーディングエージェントが先に取得するなど、依頼から呼び出し手順を変更する場合があります。正確な操作順の比較はPythonクライアントで行ってください。

ユーザーの切り替えでは、起動中のエージェントを終了し、`session.py`を使います。クライアントの保存済みOAuth認証情報とCognitoのブラウザセッションを両方解除し、PolicyセッションIDも更新します。その後、別のユーザーでログインしてエージェントを再起動します。ユーザーを変えず履歴だけを分ける操作もcommands.shにあります。

## ファイル構成

| フォルダ | 役割 |
| --- | --- |
| `app/` | Runtime上のMCPツールと固定データ |
| `terraform/` | Runtime・Gateway・Cognito・Policy・IAM |
| `scripts/` | ビルド、ユーザー作成、接続設定、比較実行、ユーザー切り替え、後片付け |
| `results/` | 実行時の比較記録（Git管理対象外） |

## 後片付け

後片付けのコマンドはcommands.sh末尾にあります。対象情報を保存してTerraform管理リソースを削除した後、RuntimeのログとRuntime・GatewayのWorkload Identityを確認・削除します。Cognitoユーザーもプールとともに削除されます。

- [Temporal Policy](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/policy-temporal.html)
- [Dogwoodのイベント・条件記述](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/policy-temporal-authoring.html)
- [Policyセッション](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/policy-session-based-temporal.html)
- [GatewayとPolicy](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/use-gateway-with-policy.html)
