# Bedrock Guardrails：単独検査とLambdaでの適用強制

同じGuardrailを2通りで使います。架空の家電メーカーの商品案内を題材に、禁止トピックと単語フィルターの違い、内容によるブロックとIAMによる呼び出し拒否の違いを確認します。

```text
① ローカルPython（develop） → ApplyGuardrail → 検査結果のみ（モデル生成なし）
② ローカルPython（develop） → Lambda → Converse → 回答／内容ブロック
                                └ 実行ロールのIAMでGuardrail省略を拒否
```

Application Inference Profileは作成しません。モデルはAWS提供の`jp.anthropic.claude-sonnet-4-6`を指定します。LambdaとローカルはPython 3.14です。

## Guardrailの設定

| 設定 | 内容 | 判定の違い |
| --- | --- | --- |
| 禁止トピック `InvestmentAdvice` | 個別の株式・金融商品の購入、売却、保有を勧める投資助言 | 文章の意味から判定 |
| 単語フィルター | 架空の社内コード名 `PROJECT-KOHARU` | 登録した語句との一致で判定 |

どちらも入力と出力を検査し、検出時は固定のブロックメッセージを返します。この例ではマスク・PII検出・プロンプト攻撃検出は設定しません。単語フィルターは登録語の検出であり、社内情報全般の流出を防ぐものではありません。

日本語の禁止トピックには**Standard tier**を使います。そのためAWS提供の`apac.guardrail.v1:0`という**Guardrail用プロファイル**を指定します。これはApplication Inference Profileとは別の仕組みで、検査がAPAC内の他リージョンへ振り分けられる場合があります。モデルの日本国内向け推論プロファイルとは処理先が異なります。

本サンプルは`DRAFT`を使用し、公開バージョンは作成しません。Guardrailの設定変更は次回の呼び出しから使用されます。設定を固定したい本番用途では、公開バージョンとそれを指定するIAM条件を利用します。

## 配置と実行

コマンドは[commands.sh](commands.sh)にまとめています。WindowsはPowerShell、macOSはシェルで、サンプル直下から区間ごとに実行してください。必要なのはuv、Terraform、AWS CLIとログイン済みの`develop`プロファイルです。SSOログインは必要時のみ実行します。

配置するのはGuardrail、Lambda、専用実行ロールとポリシー、7日保持のCloudWatchログです。API GatewayやWebサーバーは使わず、Lambda Invoke APIで同期呼び出しします。配置者にはこれらを管理する権限、Lambdaへの`iam:PassRole`、モデルの推論プロファイル参照権限、Guardrail用プロファイルへの管理権限が必要です。

ローカル実行者には対象GuardrailとAPAC宛先のGuardrail用プロファイルへの`bedrock:ApplyGuardrail`、対象Lambdaへの`lambda:InvokeFunction`が必要です。Terraformの`local_client_policy`出力で対象ARN付きの権限例を確認できます。既存の`develop`の権限は変更しません。Lambda経由の例を使うには、このアカウントで指定のClaudeモデルを利用できる必要があります。

## 比較する結果

| 経路・ケース | 期待するstatus | 確認する内容 |
| --- | --- | --- |
| local / normal | `passed` | 家電選びの質問が通る。回答は生成しない |
| local / topic | `blocked` | `topic:InvestmentAdvice`が検出される |
| local / word | `blocked` | `word:PROJECT-KOHARU`が検出される |
| local / OUTPUT | `blocked` | 手作りの回答文も単独で検査できる |
| lambda / normal | `answered` | Guardrail付きのモデル呼び出しが成功 |
| lambda / topic・word | `blocked` | Converseの`guardrail_intervened`と該当フィルターを確認 |
| lambda / normal / unguarded | `access_denied` | 同じ通常文でもGuardrailを省略するとIAMが拒否 |

例文は`scripts/client.py`の`CASES`にあります。`--text`で別の文章も指定できます。禁止トピックは確率的な検出であり、すべての言い換えで同じ判定になる保証はありません。`--expect`と`--expect-filter`は期待と異なる結果で終了コードを非0にし、検出の見逃しを成功扱いにしません。

表示と`results/`のJSONに、判定・該当フィルター・検査詳細を残します。Converseでは入力側と出力側の検査詳細を`guardrail_trace`で区別できます。Lambdaの正常例はモデル出力次第で変わります。出力側のブロックを再現しやすくするため、単独検査では固定文を`source=OUTPUT`として渡す例も用意しています。

## IAMで何を強制しているか

ローカルの認証情報は、単独検査またはLambdaを呼ぶために使います。Lambda内のBedrock呼び出しは**Lambda実行ロールの一時認証情報**で行われます。ローカルの認証情報をLambdaへ渡す構成ではありません。

実行ロールは対象モデルへの推論をAllowしたうえで、`bedrock:GuardrailIdentifier`が**指定Guardrailのバージョン番号なしのARN**と一致しない場合、`InvokeModel`と`InvokeModelWithResponseStream`を明示的にDenyします。Converseも`bedrock:InvokeModel`で認可されるため対象です。未指定の場合も拒否され、Guardrailを別のものや公開バージョンへ変えても拒否されます。API側では`guardrailVersion="DRAFT"`を指定し、IAM条件側ではARNに`:DRAFT`を付けません。

`unguarded`は検証用の切り替えです。Lambdaのコードが拒否を模擬するのではなく、`guardrailConfig`を省略して実際にConverseを呼びます。同じ質問の`guarded`が成功することを先に確認し、その後に`unguarded`のエラーメッセージで明示的Denyを確認してください。単なる`AccessDeniedException`だけでは、モデルアクセス不足など他の権限エラーと区別できません。

Lambda InvokeのHTTP成功は、Bedrockでの推論成功を意味しません。クライアントはLambdaの`FunctionError`と返却した`status`を確認します。認可以外のBedrockエラーは通常のLambda実行エラーとして扱い、Guardrailのブロックに置き換えません。

このIAM制限は**このLambda実行ロールだけ**に適用されます。ローカルの利用者やアカウント全体に推論制限を設定するものではありません。また、IAMはGuardrail指定を必須にしますが、入力の部分検査タグまで禁止するものではありません。このサンプルは部分検査タグを使わず、ユーザー文を通常のtextとして渡します。

## ファイル構成

| ファイル | 役割 |
| --- | --- |
| `terraform/guardrail.tf` | 禁止トピック・禁止語（DRAFT） |
| `terraform/lambda.tf` | Lambda、IAM強制、ログ、ZIP作成 |
| `terraform/providers.tf`・`outputs.tf` | プロバイダー・モデル設定・クライアント設定 |
| `app/lambda_function.py` | Guardrail付き／なしのConverse呼び出し |
| `scripts/client.py` | ApplyGuardrail単独検査、Lambda呼び出し、結果確認 |
| `commands.sh` | 準備・比較・片付けのコマンド |

## 片付け

利用後は`commands.sh`末尾の片付け区間でTerraform管理のリソースを削除します。Lambdaのログも削除対象です。ローカルの実行記録は残り、Git管理からは除外しています。

## 公式資料

- [ApplyGuardrailの単独利用](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails-use-independent-api.html)
- [Converseへの適用](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails-use-converse-api.html)
- [IAMでGuardrailを必須にする](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails-permissions-id.html)
- [禁止トピック](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails-denied-topics.html)
- [単語フィルター](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails-word-filters.html)
- [Standard tier](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails-tiers.html)
- [Guardrailのクロスリージョン権限](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrail-profiles-permissions.html)
