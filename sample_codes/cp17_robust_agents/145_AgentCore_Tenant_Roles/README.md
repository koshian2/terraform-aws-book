# テナントIDを伝播し、テナント別IAMロールでDynamoDBを読む

共通のGateway・Runtimeから、ログインした会社の読み取りロールを引き受け、その会社のDynamoDBテーブルからデータを取得します。同じ問い合わせID`T001`でも所属会社によって結果が変わります。テナントID・テーブル名・ロールARNは業務ツールの引数に公開しません。

| Cognitoユーザー | 所属 | T001の内容 |
| --- | --- | --- |
| alice | tenant-a | 商品が届きません。 |
| bob | tenant-b | 請求書の宛名を変更してください。 |

## 構成

```text
Codex / Claude Code / Pythonクライアント
  → Cognitoでログイン（tenant_id付きアクセストークン）
  → AgentCore Gateway（JWT検証）
  → Request Interceptor（JWTから所属を抽出し専用ヘッダーへ設定）
  → AgentCore Runtime上のMCP（GatewayロールのSigV4で認証）
  → STS AssumeRole → 会社別reader → 会社別DynamoDBテーブル
```

MCPツールはRuntime上で公開します。コーディングエージェントはGatewayにHTTPで直接接続し、ローカル中継サーバーは使いません。サンプル側に回答生成用モデルはなく、取得した結果の説明はコーディングエージェントが行います。

## テナント情報と権限のつなぎ方

1. 管理者がCognitoユーザーに変更不可の`custom:tenant_id`を設定します。OAuthクライアントからこの属性を書き換える権限は付与しません。
2. Pre Token Generation Lambdaが所属を確認し、アクセストークンに`tenant_id`を追加します。CognitoはESSENTIALS、トリガーはV2_0です。
3. GatewayがJWTを検証し、Request Interceptorに受信ヘッダーを渡します。Interceptorは検証済みJWTから所属を抽出します。JWTのデコードだけを認証として使う例ではありません。
4. Interceptorが`X-Amzn-Bedrock-AgentCore-Runtime-Custom-Tenant-Id`を設定します。呼び出し元が同名ヘッダーを送っても、JWT由来の値で上書きします。
5. Gateway TargetとRuntimeの両方でこのヘッダーの受け渡しを許可します。Runtimeの直接呼び出しは、Gatewayロール以外をリソースポリシーで拒否します。
6. Runtimeはリクエストごとに一時認証情報を取得します。共有の環境変数や認証情報キャッシュを書き換えず、別会社の要求との混在を避けます。

## テナント別ロールによるアクセス制御

Runtimeの実行ロールには、2つのreaderロールを引き受ける`sts:AssumeRole`だけをデータアクセス用に許可し、DynamoDBの読み取り権限を直接付けません。各readerロールはRuntimeだけを信頼し、自社テーブルの`dynamodb:GetItem`だけを許可します。

Runtimeはサーバー側の対応表から所属に合うロールARN・テーブル名を選びます。公開ツールは`get_inquiry(ticket_id)`の1つです。更新・削除や任意テーブルの参照は提供しません。

## 信頼する範囲

所属の欠落や未知のテナントは拒否し、既定の会社に振り分けません。STSで失敗したときにRuntime自身の認証情報で読み直すこともありません。

STSは元のCognito JWTを検証しません。正しい所属を受け渡し、それに対応するロール・タグを選ぶ処理は信頼する前提です。共通Runtimeは両社向けの認証情報を発行できるため、Runtime自体が侵害されても会社間を完全に隔離できる構成ではありません。

## 実行

Python 3.14、uv、Terraform 1.12以降、AWS CLIを使います。プロファイルは`develop`、リージョンは`ap-northeast-1`です。変更する場合は`terraform/variables.tf`の設定を調整します。

操作は[commands.sh](commands.sh)に集約しています。サンプル直下で、WindowsではGit Bash、macOSではbashからセクションごとに実行してください。

1. 依存関係とZIPを作成し、Terraformでデプロイします。
2. alice／bobを作成します。シェルに表示するユーザー名を確認し、ユーザー作成時に設定したパスワードでログインしてください。
3. Pythonクライアントをalice・bobで実行します。毎回Cognitoのブラウザセッションを終了してからログインし、取得結果を`results/`に保存します。JWTや一時認証情報は保存しません。
4. Codex・Claude Codeの設定を生成します。コールバックURLをCognitoに登録し、ログイン画面に到達できることも確認します。
5. Codexは`codex/`、Claude Codeは`claude-code/`から起動し、認証します。ユーザー切り替え操作も`commands.sh`にあります。

Gateway Target作成前に60秒待機します。初回の登録で認可エラーになった場合は、少し時間を置いてplan・applyを再実行してください。

## 確認する結果

| 確認 | 期待結果 |
| --- | --- |
| alice／bobでT001を取得 | 各社の本文だけを返す |
| 存在しないT999 | `found: false` |
| 他社のtenant_idをツール引数に追加 | 未定義の引数として拒否 |
| 他社のテナントヘッダーを送信 | JWT由来の所属で上書きし、自社の本文を返す |

`permissions.py`はIAMシミュレーターで、各readerロールは自社のみ許可、Runtimeは両テーブルとも直接取得不可となることを確認します。これはポリシー評価の検証であり、他社テーブルに対する実APIのAccessDeniedを取得した記録とは区別してください。

このサンプルのAWSへのデプロイ後の実行記録はまだありません。上表は期待結果です。ローカル検証でAWS APIを置き換えた結果を、IAMによる拒否の実測として扱わないでください。

## コーディングエージェントでの質問例

> agentcore-tenants MCPを使って、問い合わせT001の内容を教えてください。

aliceで確認した後、bobに切り替えて同じ依頼をします。MCP名を明示し、会社は引数で指定しません。

## ファイル構成と後片付け

- `app/`：RuntimeのMCP、DynamoDB取得、2種類のLambda。
- `terraform/`：Cognito・Gateway・Runtime・IAM・DynamoDBの定義。
- `scripts/`：ビルド、ユーザー作成、ログイン、接続設定、確認、後片付け。
- `codex/`・`claude-code/`：エージェントごとの作業ディレクトリ。接続設定はデプロイ後に生成します。

後片付けは`commands.sh`末尾のコメントアウトされたセクションを使います。Terraformによる削除前に対象を記録し、削除後にRuntimeのログとWorkload Identityも削除します。`results/`の確認記録はGit管理外です。
