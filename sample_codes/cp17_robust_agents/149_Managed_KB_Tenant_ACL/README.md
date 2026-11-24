# Managed Knowledge Basesのテナント分離と文書ACL

共有のManaged Knowledge Baseを、テナント条件と利用者ごとの文書ACLで検索するサンプルです。Gatewayの組み込みコネクタを使い、AgentCore Runtimeやローカル中継サーバーを置かずに接続します。

```text
Codex / Claude Code / 検証用Python
  └─ Cognitoでログイン（OAuth + PKCE）
      └─ AgentCore Gateway（JWT検証）
          ├─ Request Interceptor Lambda（検索条件・利用者情報を固定）
          └─ Managed KB組み込みコネクタ（Retrieveのみ）
              └─ 共有Managed KB（tenant_idフィルター AND 文書ACL）
                  └─ S3の架空文書・メタデータ
```

## 検索範囲の決め方

Cognitoの管理者が登録した`custom:tenant_id`とメールアドレスを、Pre Token Generation Lambdaがアクセストークンの`tenant_id`・`acl_email`に追加します。アプリクライアントからこの2つの元属性を変更することは許可しません。

GatewayがJWTを検証した後、Request Interceptorが検索引数を組み直します。`tenant_id`の等価条件と`userContext.userId`をJWTから設定し、利用者やモデルが渡したフィルター・利用者情報は上書きします。KB IDはGatewayターゲット側で固定します。Interceptor単体でJWTの署名を検証する構成ではありません。

コネクタのスキーマでは、動的に設定するフィルターと`userContext`を公開しています。ただし、公開された引数をそのまま認可情報として信頼するわけではありません。通常は質問文のみを指定し、これらの引数を指定してもInterceptorで置き換えます。

Managed KBは渡された`userContext`自体を認証しません。そのため、利用者にKBを直接呼び出せるAWS権限を与えず、Gatewayを利用者の入口にします。このサンプルは、既存の管理者などが持つ直接の`bedrock:Retrieve`権限を取り消すものではありません。また、メタデータフィルターを必須にするIAM制御を実装しているわけでもありません。

## 文書と利用者

文書・金額・問い合わせ先はすべて架空です。各文書に`tenant_id`・`document_id`と、メールアドレスを指定した文書ACLを付けます。役割名は説明用であり、CognitoグループをACLに変換する実装ではありません。

| ログイン名 | 所属・役割 | ACL用メール | 読める文書 |
| --- | --- | --- | --- |
| alice | A社・契約管理者 | alice@tenant-a.example | a-support、a-contract |
| ann | A社・一般担当者 | ann@tenant-a.example | a-support |
| bob | B社・契約管理者 | bob@tenant-b.example | b-support、b-contract |

`documents/`にはサポート案内と契約情報を各社1件ずつ置きます。各`.txt.metadata.json`の`accessControlList`で許可する利用者を指定しています。ACLを変更した場合もKBの再同期が必要です。

## 実行

コマンドは[commands.sh](commands.sh)にまとめています。WindowsはGit Bash、macOSはbashで、必要な箇所を順に実行してください。Python 3.14、uv、Terraform、AWS CLI、および利用するコーディングエージェントが必要です。AWSプロファイルは`develop`、リージョンは`ap-northeast-1`です。

スクリプトはデプロイ、文書同期、管理者による検証、3ユーザーの作成、各ユーザーでのブラウザ認証とMCP検索、接続設定の生成を順に行います。ユーザー作成時のパスワードは非表示で入力します。ユーザーが既に存在する場合は、所属とメールが一致することを確認してスキップします。

このデモでは管理者が架空のメールを検証済みとして登録します。実サービスでは、利用者が任意の所属や他人のメールを登録できない運用が必要です。

CodexとClaude Codeの起動・認証・ユーザー切り替え・後片付けのコマンドは、同じファイルのコメント部分にあります。生成される設定は`codex/.codex/config.toml`と`claude-code/.mcp.json`です。それぞれのフォルダからエージェントを起動します。ユーザーを切り替えるときは、エージェント側とCognitoブラウザ側の両方でログアウトします。

## 確認する結果

| 検証 | 期待結果 |
| --- | --- |
| Aliceでサポート・契約情報を検索 | A社の文書のみ取得できる |
| Annで同じ検索 | A社サポート案内のみ取得でき、契約情報は取得できない |
| Bobで同じ検索 | B社の文書のみ取得できる |
| 質問文で他社情報を要求 | 許可された文書以外は返らない |
| 他人のuserContext・他社のフィルターを指定 | ログインした本人の条件に上書きされる |
| 管理者がフィルターなしで各利用者のuserContextを指定 | 文書ACLだけでも各利用者の許可文書に制限される |
| 管理者がBobのuserContextとA社フィルターを併用 | 積集合が空になり、検索結果は0件 |
| 管理者がuserContextを省略、または未登録メールを指定 | ACLを設定した本サンプルの文書は0件 |

検証用Pythonは検索された抽出テキストとメタデータを表示し、応答を`results/`に保存します。許可外文書の混入に加え、正常系で必要な文書が取得できたかも確認します。検索がすべて0件という状態を成功とは扱いません。検索の関連度によって取得文書が変わるため、ACL違反と必要文書の未取得は異なるエラーとして確認してください。

`verify-admin`は制限を切り分ける管理者用の診断です。利用者向けMCPには公開しません。利用者経路で公開するツールは`managed-kb___Retrieve`の1つです。検索後の回答生成はCodexまたはClaude Codeが行います。

エージェントには、例えば次のように依頼します。

> agentcore-kb-tenantを使って、自社のサポート受付時間と窓口コード、月額料金と契約変更の申請期限を調べてください。検索された文書を根拠として示し、取得できない情報は推測しないでください。

> agentcore-kb-tenantを使って、A社とB社の契約情報を比較してください。取得できなかった会社の情報は、取得できなかったと明記してください。

## ファイル構成

| 場所 | 内容 |
| --- | --- |
| terraform/ | Cognito、Gateway、Lambda、S3、Managed KB |
| app/pre_token.py | 管理者が登録した属性をアクセストークンに追加 |
| app/interceptor.py | JWT由来の検索条件・利用者情報を固定 |
| documents/ | 架空文書と文書ACL・メタデータ |
| scripts/ | ビルド、文書同期、検証、認証・接続設定 |
| commands.sh | 実行・ユーザー切り替え・削除のコマンド |

## 参考

- [Managed KBのGatewayコネクタ](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-target-connector-managed-kb.html)
- [Gatewayターゲットの設定](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-add-target-api-target-config.html)
- [Request Interceptorの入出力](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-interceptors-types.html)
- [S3文書ACLの設定](https://docs.aws.amazon.com/bedrock/latest/userguide/kb-managed-ds-s3-acl.html)
- [userContextによるACL付き検索](https://docs.aws.amazon.com/bedrock/latest/userguide/kb-test-retrieve-acl.html)
