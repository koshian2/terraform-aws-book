# GatewayでMCPの呼び出し回数を制限する

足し算ツールを、全利用者合計で毎分2回の設定にする例です。Runtimeのツールにはカウンターを持たせず、AgentCore Gatewayで呼び出し量を制御します。

```text
Python / Codex / Claude Code
  → Cognito JWT → AgentCore Gateway（レート制限）
  → IAM SigV4 → AgentCore Runtime / MCP
```

Runtimeが公開するツールは`add(a, b)`の1つです。Gatewayでの名前は`calculator-runtime___add`となります。入力は−1,000,000〜1,000,000の整数で、結果は`a`・`b`・`sum`です。

## 制限の範囲

レート制限の集計キーは`toolName`だけです。ユーザーやクライアントごとの枠ではなく、同じツールを呼び出す全利用者で枠を共有します。初期化とツール一覧取得は、このツール呼び出し数の制限対象に含めません。Runtimeへの直接呼び出しは、GatewayのIAMロール以外からは拒否します。

`terraform/rate_limit.tf`のCloudFormation Stackで`AWS::BedrockAgentCore::GatewayRateLimit`を管理します。固定しているAWS Provider 6.66.0の専用リソースがないため、この部分だけCloudFormationを使います。削除もTerraformから行います。

| 項目 | 設定 |
| --- | --- |
| 制限ID | `add-per-minute` |
| 集計キー | `toolName` |
| 対象 | `calculator-runtime___add` |
| 種類 | `requests` |
| レート | 毎分2回（`requests_per_minute`で1〜10に変更可能） |

**必ず3回目で拒否される、毎分00秒に枠が戻る、とは考えません。** AWSの説明では、レート制限は結果整合性（eventual consistency）に基づいており、作成直後やしばらく使っていない制限は設定以上の要求を許可する場合があります。毎分数回の低いレートでは精度のばらつきも大きくなります。この例では、成功回数を固定せず、制限の発生と回復を観察します（詳細は[適用精度と制限時の挙動](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-rate-limits-enforcement.html)を参照）。

また、評価サービスがタイムアウトした場合はfail-openとなります。レート制限は利用量の調整・バックエンド保護に使い、厳密な課金上限や認可の代わりにはしません。

## 準備と実行

Python 3.14、uv、Terraform 1.12以上2.0未満、AWS CLIを使用します。FastMCPは4.1.1、AWSプロファイルは`develop`、リージョンは東京が既定です。設定変更は`terraform/terraform.tfvars`で行い、複数デプロイするときは`name`も変えます。

実行コマンドは[commands.sh](commands.sh)にまとめています。サンプル直下でセクションごとに実行し、ZIP作成後にTerraformでデプロイします。ターゲット登録前には、権限反映のため60秒待機します。反映完了の保証ではないため、初回に認可エラーが出た場合は少し時間を置いて再実行してください。

デプロイにはS3・IAM・Cognito・AgentCore・CloudFormationの管理権限と`iam:PassRole`が必要です。後片付けでは自動生成ログとWorkload Identityの削除権限も使います。

ユーザー`reader`を作成し、ブラウザでログインします。パスワードは対話入力で設定し、Terraform stateには保存しません。Pythonのログインでは同じPCの8765番ポートを使います。トークンはメモリ内だけで保持します。

## Pythonで制限と回復を確認する

`client.py verify`はログイン後、レート設定の反映を35秒待ってから次を行います。

1. 足し算を意図的な待機なしで順番に呼び出します。最大60回、呼び出し開始期限は180秒です。各通信にも30秒のタイムアウトがあります。
2. 最初の制限エラーで停止し、MCPコード`-32003`、制限ID`add-per-minute`、`metric=requests`、有効な`retryAfter`を確認します。認証エラーや別のサービス上限による拒否は成功扱いにしません。
3. 制限中にもツール一覧を取得できることを確認します。
4. `retryAfter`を切り上げて1秒の余裕を加えて待ち、足し算が成功することを確認します。回復待ちは180秒の期限と最大10回の再試行で打ち切ります。

制限が観測できない場合も検証失敗として停止します。低レートの精度やほかのクライアントからの利用に影響されるため、成功回数だけで設定の正否を判断しないでください。Pythonとコーディングエージェントは同時に呼び出さず、結果を比較します。

Pythonは小さなJSON-RPCクライアントで、MCPのJSON/SSE応答とHTTP 429のエラー本文を読みます。暗黙のPOST再試行は行わず、回復確認だけ明示的に待機・再試行します。送信・応答時刻、HTTPステータス、リクエストID、MCP応答を`results/run-*.json`に残します。これは足し算のデモ用記録で、トークンは含みません。

## コーディングエージェントで試す

Codexは設定生成後に`codex/`をプロジェクトとして開きます。Claude Codeは`claude-code/`で起動し、`/mcp`から認証します。どちらもCognitoでは`reader`でログインします。MCP名は`agentcore-rate-limit`です。

> agentcore-rate-limitを使って、1+1、2+2、3+3と順番に、最大20件の足し算をしてください。毎回MCPに計算を依頼し、意図的な待機を入れず、レート制限になったら再試行せず停止してください。成功回数とエラー内容を報告し、設定は変更しないでください。

モデルの判断時間やクライアント内部の再試行で、エラーが表に出ない場合があります。正確な応答の記録と回復確認はPythonで行います。

## ファイル構成と後片付け

| フォルダ | 役割 |
| --- | --- |
| `app/` | Runtimeで公開する足し算MCP |
| `terraform/` | Runtime・Gateway・Cognito・IAM・レート制限 |
| `scripts/` | ビルド・ログイン・接続設定・呼び出し・後片付け |
| `results/` | 実行時の記録（Git管理対象外） |

後片付けはcommands.sh末尾の手順です。対象を記録してTerraformで削除した後、RuntimeのログとRuntime・GatewayのWorkload Identityも削除します。

- [Gatewayレート制限](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-rate-limits.html)
- [CloudFormation GatewayRateLimit](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-bedrockagentcore-gatewayratelimit.html)
