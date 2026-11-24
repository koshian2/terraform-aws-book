# テナント別・Tier別にMCPの呼び出し回数を制限する

足し算MCPの利用枠をテナントごとに分け、Freeは毎分2回、Proは毎分10回に設定します。同じテナントのユーザーは枠を共有します。

| ユーザー | テナント | Tier | テナント全体の設定値 |
| --- | --- | --- | --- |
| alice / alice2 | tenant-a | Free | 2回/分を2人で共有 |
| bob | tenant-b | Free | Aとは別に2回/分 |
| carol | tenant-c | Pro | 10回/分 |

```text
Python / Codex / Claude Code
  → Cognitoログイン → Pre Token Generation Lambda
  ← tenant_id・tierを含むアクセストークン
  → Gateway（JWT検証 → テナント・Tier別レート制限）
  → IAM SigV4 → Runtime / add MCP
```

MCPツールはRuntimeで公開し、クライアントはGatewayに直接HTTP接続します。LambdaはCognitoのトークン発行時に使い、ツール呼び出し時のInterceptorではありません。

## 所属と利用枠

管理者がユーザー作成時に変更不可の`custom:tenant_id`を設定します。CognitoのESSENTIALSプランとV2_0のPre Token Generationを使い、LambdaがTerraformの`local.tenant_tiers`からTierを決め、アクセストークンに`tenant_id`と`tier`を追加します。所属が欠ける・未知のテナント・不正なTierではトークン発行を失敗させます。OAuthクライアントから所属属性を書き換えることも許可しません。

レート制限のキーは`toolName × $.context.jwt.tier × $.context.jwt.tenant_id`です。Free／Proのエントリーの末尾にテナントの`*`を指定します。これは全テナント共通枠ではなく、実際のテナント値ごとに枠を分ける指定です。ユーザーIDはキーに含めないので、aliceとalice2は枠を共有します（詳細は[集計キーの仕様](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-rate-limits-dimensions.html)を参照）。

ツールは`calculator-runtime___add`の1つです。−1,000,000〜1,000,000の整数2つを受け取り、`a`・`b`・`sum`を返します。Runtimeの直接呼び出しはGatewayのIAMロール以外から拒否し、制限の迂回を防ぎます。

設定は`terraform/rate_limit.tf`の`tenant_tiers`・`tier_rates`で管理します。AWS Provider 6.66.0にはレート制限の専用リソースがないため、この部分はTerraform管理のCloudFormation Stackでデプロイ・削除します。

Tier変更は新しく発行したJWTから有効です。既存トークンは以前のTierを保持し、Tierもキーに含まれるため変更前後で枠が別になります。即時失効や利用量の引き継ぎはこの例では扱いません。

## 準備と実行

Python 3.14、uv、Terraform 1.12以上2.0未満、AWS CLIを使います。FastMCPは4.1.1、AWSプロファイルは`develop`、リージョンは東京が既定です。環境の変更は`terraform/terraform.tfvars`で行い、複数デプロイする場合は`name`も変更します。

実行コマンドは[commands.sh](commands.sh)にまとめています。サンプル直下でセクションごとに実行します。Runtime用とトークン発行Lambda用のZIPを作成してからデプロイします。ターゲット登録前に権限反映のため60秒待機しますが、反映完了を保証する値ではありません。認可エラーが出た場合は少し時間を置いて再実行してください。

デプロイにはS3・IAM・Cognito・Lambda・AgentCore・CloudFormation・ログの管理権限と`iam:PassRole`が必要です。後片付けではWorkload Identityの削除権限も使います。

表の4人を作成し、それぞれパスワードを対話入力で設定します。パスワードはTerraform stateに保存しません。ログインするユーザーはシェルに表示します。Pythonはログイン前にブラウザのCognitoセッションを解除し、ログイン後のusername・tenant_id・tierも照合します。JWTのローカルデコードは取り違え防止用で、署名検証はGatewayが行います。

Pythonとブラウザは同じPCで使い、ログインの8765番・ログアウトの8768番ポートを空けてください。`--no-browser`では表示されたログアウト・ログインURLを手動で開きます。トークンはメモリ内だけに保持します。

## Pythonで確認する

`client.py verify --user alice`と`--user carol`で、それぞれの制限発生・制限中の一覧取得・待機後の回復を確認します。設定反映を35秒待ち、最大60回・呼び出し開始期限180秒で観測します。最初の制限で停止し、`retryAfter`に従って回復を確認します。回復待ちは180秒の期限と最大10回で打ち切ります。

`compare.py`はテナント共有・分離をまとめて観察します。4人分のログインを先に済ませるため、比較途中にブラウザ操作を挟みません。

1. AWS上のレート制限が期待するACTIVEな設定であることを確認します。
2. aliceで5並列・最大60回・120秒以内の負荷をかけ、全件が制限されたバッチを観測します。
3. aliceとalice2が拒否され、同時にbobが成功するかを比較します。
4. bobでも制限に達するまで呼び出し、bobが拒否されてcarolが成功するかを比較します。
5. carolの制限発生と待機後の回復を確認します。

比較条件が観測できなければ`INCONCLUSIVE`（終了コード2）、認証・通信などのエラーは`ERROR`（1）とします。全項目の観測成功は`PASS`（0）です。比較で未判定になっても可能な後続項目は進めますが、負荷上限や通信エラーで停止した場合はそこまでの記録を保存します。

`results/`にはユーザー・所属・Tier、送信時刻、HTTPステータス、MCP応答、判定結果を保存します。認証トークンは保存しません。MCPコード`-32003`、制限ID`add-per-minute`、`metric=requests`を確認し、別の制限や認証エラーを成功扱いしません。

## コーディングエージェントで比較する

Codexは`codex/`、Claude Codeは`claude-code/`をプロジェクトとして開きます。接続設定は各configureスクリプトで生成します。Codexはコールバック登録後、ログイン画面への到達を3回連続で確認します。最初はalice、次にcarolで同じプロンプトを試します。

> agentcore-tier-rate-limitを使って、1+1、2+2、3+3と順番に最大30件の足し算をしてください。毎回MCPに計算を依頼し、意図的な待機を入れず、エラーになったら再試行せず停止してください。設定は変更せず、成功回数・経過時間・停止理由を報告してください。

ユーザー切り替え時は、クライアントのOAuth認証情報とCognitoのブラウザセッションの両方を解除します。Codexでは終了後に`session.py --client codex`を使い、Claude Codeでは`/mcp`で認証解除後に終了し、`session.py`でブラウザからログアウトします。通常と同じブラウザプロファイルを使ってください。チャットを新しくするだけではユーザーは変わりません。

## 結果の読み方

毎分2回／10回は設定値であり、「必ず3回目／11回目に拒否」「Proは成功回数が必ず5倍」とはしません。レート制限は結果整合性（eventual consistency）に基づいており、呼び出し開始直後や低レートでは超過許可やばらつきが生じ得ます。テナントの共有・分離も単発比較だけで必ず観測できるものではありません（詳細は[適用精度の説明](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-rate-limits-enforcement.html)を参照）。

他クライアントの呼び出しは止めて比較します。一時ユーザーを新しくしてもテナントIDが同じなら利用枠は共有されます。Codexなどの判断時間・内部再試行も結果に影響するため、正確な応答記録はPythonで確認します。

JWTの集計キーが欠けると該当制限はスキップされるため、トークン発行時の所属・Tier検証が重要です。またレート制限はfail-openのため、厳密な課金上限や認可の代わりにはしません。

## ファイルと後片付け

| フォルダ | 内容 |
| --- | --- |
| `app/` | 足し算MCPとトークン発行Lambda |
| `terraform/` | AWSリソース・レート制限・テナント対応表 |
| `scripts/` | ビルド・ユーザー作成・ログイン・比較・接続設定・後片付け |
| `results/` | 実行記録（Git管理対象外） |

後片付けはcommands.sh末尾の手順です。Terraform管理リソースに加え、自動生成されたRuntimeログとRuntime・GatewayのWorkload Identityも削除します。Cognitoユーザーはプールとともに削除されます。

依存パッケージの同期、Runtime・LambdaのZIP作成、Terraformのfmt・init・validate、CLI起動を確認しています。ローカルHTTPで足し算と不正入力の拒否を確認し、トークン発行Lambdaの所属・Tier検証、ログインユーザーの取り違え検知、模擬応答による比較のPASS／INCONCLUSIVEと回復処理も確認しました。AWSへのデプロイ、ログイン、実機でのTier別制限・テナント共有・分離は未確認です。
