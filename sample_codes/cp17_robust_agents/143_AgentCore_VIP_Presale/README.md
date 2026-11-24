# VIP先行販売をPolicyとRequest Interceptorで制御する

VIPだけが利用できる予約ツールで、指定商品が先行販売対象か、受付期間内かを実行前に検査します。テナント、LLM、在庫、残枠、予約の永続化は扱いません。Runtimeはデモの受付結果を返します。実行コマンドは[commands.sh](commands.sh)にまとめています。

## 構成と評価順序

```text
Codex / Claude Code / Python
  → CognitoのJWTをGatewayで検証
  → Request Interceptor（Lambda）：商品と受付期間を検査
  → AgentCore Policy（Cedar / ENFORCE）：VIPの呼び出しを許可
  → AgentCore Runtime（FastMCP）：デモ受付結果を返す
```

Request InterceptorはPolicyより先に実行されます。商品条件が通っても、VIP資格がなければRuntimeへは進みません。Interceptorが拒否応答を返す場合は、その時点で処理を終了します。[AWSの評価順序の説明](https://aws.amazon.com/blogs/machine-learning/secure-ai-agents-with-policy-and-lambda-interceptors-in-amazon-bedrock-agentcore-gateway/)

MCPツールはRuntimeに1つ公開し、GatewayのリモートMCPへHTTPで接続します。Runtimeへの直接呼び出しはGatewayロール以外を拒否します。

| 担当 | 検査すること |
| --- | --- |
| Cognito / Gateway | JWTの発行元、クライアント、スコープなど |
| Request Interceptor | 商品IDがカタログに存在するか、先行販売対象か、現在時刻が受付期間内か |
| Policy | CognitoのグループがVIPか |
| Runtime | 引数の型・商品IDの形式を検証し、デモの受付結果を返す |

会員資格は引数で受け取らず、Cognitoが発行した`cognito:groups`クレームをPolicyで参照します。このサンプルのグループは管理者が作成する`regular`と`vip`の2つに限定しています。AWSの例に合わせてグループタグを`like "*vip*"`で照合するため、`nonvip`などvipを含む別グループを追加すると一致します。グループを増やす場合は、その命名・クレームの設計に合わせて認可条件も変更してください。

## 商品データと期待結果

`app/products.json`をLambdaへ同梱します。受付開始を含み、受付終了を含まないUTCの期間で比較します。時刻はLambda側で取得し、呼び出し元から指定させません。

| 会員 | 商品 | 条件 | 期待結果 |
| --- | --- | --- | --- |
| regular | A：限定ミル | 先行販売対象・期間内 | Policyが拒否 |
| vip | A：限定ミル | 先行販売対象・期間内 | Runtimeがデモ受付 |
| vip | B：通常マグ | 先行販売対象外 | Interceptorが拒否 |
| vip | C：次回ケトル | 受付開始前 | Interceptorが拒否 |

教材を実行するたびに日時を編集しなくてよいよう、Aの期間は2020年から2099年、Cの開始は2099年に固定しています。実際の販売日程ではなく検証用の設定です。期間終了・不明な商品・想定外の引数も拒否します。商品データの読み取りや検査に失敗した場合も、要求を通しません。

一般会員がBやCを指定した場合は、Policyより先にInterceptorで拒否されます。Policyの拒否を切り分けるため、一般会員の検証では商品条件を満たすAを使います。Interceptorの通過ログはVIP資格の認可成功を意味しません。

## 実行

Python 3.14、uv、Terraform 1.12以上2未満、AWS CLIを使用します。FastMCPは4.1.1、AWSプロバイダーは6.66.0です。AWSプロファイルは`develop`、リージョンは東京が既定です。変更する場合は`terraform/variables.tf`を編集します。

サンプル直下でcommands.shを区間ごとに実行してください。Runtime用ZIPとLambda用ZIPをビルドしてからTerraformを適用します。GatewayのRuntime接続前には認可反映のため60秒待機します。反映を保証する値ではないため、ターゲット登録でAuthorization errorになった場合は、少し時間を置いてplan・applyを再実行してください。

`regular`と`vip`の2ユーザーを作成し、それぞれ指定グループへ登録します。パスワードは対話入力で、Terraformには保存しません。ユーザー作成後にグループを変更した場合は、ログインし直して新しいトークンを取得してください。

Pythonクライアントはユーザーの取り違えを防ぐため、各検証前にCognitoのブラウザセッションを終了します。表示されたユーザー名でログインしてください。一般会員はAを1回、VIPはA・B・Cを各1回呼び、期待結果と比較します。拒否後の自動再試行はしません。トークンはメモリにのみ保持します。

| 応答 | 記録上の判定 |
| --- | --- |
| PolicyのJSON-RPCエラー`-32002` | `policy_denied` |
| Interceptor独自のJSON-RPCエラー`-32048` | `not_presale_product`などの理由 |
| Runtimeの正常結果 | `demo_accepted`、`persisted: false` |

HTTP 200だけで成功とせず、JSON-RPCのエラーも判別します。結果は`results/regular-日時.json`と`results/vip-日時.json`に保存します。想定外の通信・認証エラーは成功扱いしません。Request Interceptorの応答は、Gatewayの`transformedGatewayResponse`契約を使います。[AWSのInterceptor入出力仕様](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-interceptors-types.html)

LambdaのCloudWatch Logsには商品条件の判定、Runtimeのログには`demo_reservation_accepted`を出します。認証トークンやイベント全体はログに出しません。48の検証にTransaction Searchの設定は不要です。

## Codex / Claude Code

commands.shのconfigure処理で設定を生成し、Codexは`codex/`、Claude Codeは`claude-code/`から起動します。Cognitoのコールバック登録とログイン画面への到達を確認してから設定を生成します。

VIPでのサンプルプロンプト:

> agentcore-vip-presaleのMCPを使って、商品A・B・Cの先行予約をそれぞれ1回ずつ試してください。受け付けられた商品と拒否された商品、その理由を表示し、拒否された要求は再試行しないでください。

一般会員でのサンプルプロンプト:

> agentcore-vip-presaleのMCPを使って、商品Aの先行予約を試してください。利用可能なツールがなければ、その旨を報告してください。

一般会員ではPolicyによってツール一覧から予約ツールが見えなくなる場合があります。そのため、既知のツール名への直接呼び出しが拒否される確認はPythonクライアントで行います。会員を切り替える場合はエージェント側のMCP認証とCognitoのブラウザセッションの両方を終了し、再ログインしてください。Codexの切り替え手順はcommands.shにあります。

## ファイルと片付け

| 場所 | 内容 |
| --- | --- |
| `app/server.py` | Runtimeの予約ツール |
| `app/interceptor.py`・`products.json` | 実行前の商品検査と固定カタログ |
| `terraform/` | Cognito、Policy、Gateway、Lambda、Runtime |
| `scripts/` | ビルド、認証・設定、比較実行、片付け |
| `results/` | ローカル記録（Git管理対象外） |

片付けはcommands.sh末尾の手順を使用します。Terraform削除前に対象を記録し、削除後にRuntimeのログとRuntime・GatewayのWorkload Identityを片付けます。LambdaのログはTerraformで削除します。

この例は入口での認可を比較する教材です。実際に予約を保存するシステムでは、受付終了や在庫などの業務条件を、更新処理側でも一貫して保証する必要があります。
