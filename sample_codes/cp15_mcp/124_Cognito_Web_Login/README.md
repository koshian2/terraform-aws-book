# CognitoでWebアプリにログインする

Cognitoユーザープールに作ったユーザーでログインし、発行されたJWTの中身を確認するデモです。WebブラウザとPythonから、同じユーザープールを使います。Pythonは3.14です。

## 何を作るか

```text
ブラウザ → CloudFront → S3（HTML・JavaScript）
  └─ Cognitoのログイン画面 → 認可コード → トークン → クレーム表示

Python → Cognito API（boto3）→ トークン取得・検証・更新・失効
```

HTMLとJavaScriptは公開します。ログイン後に、取得したトークンのクレームを表示します。ページ自体へのアクセスを認証で制限する構成ではありません。S3への直接アクセスは許可せず、CloudFront経由で配信します。

ユーザープールはユーザーと認証を管理します。アプリクライアントは、そのユーザープールを使うアプリの設定です。ブラウザ用とPython用を分け、ブラウザには認可コードフロー＋PKCE、Pythonには仕組みの確認用に `USER_PASSWORD_AUTH` を許可します。どちらもクライアントシークレットを持たない公開クライアントです。IDプールは使いません。

## 構成

```text
124_Cognito_Web_Login/
├── web/
│   ├── index.html        # ログイン・トークン表示
│   └── app.js            # 認可コード＋PKCE、更新、ログアウト
├── scripts/
│   └── client.py         # ユーザー作成、boto3の認証デモ
├── terraform/
│   ├── providers.tf     # AWSプロファイル・リージョン
│   ├── cognito.tf       # ユーザープール・アプリクライアント
│   ├── web.tf           # S3・CloudFront・公開設定JSON
│   └── outputs.tf
├── pyproject.toml
└── commands.sh
```

`config.json` はTerraformがS3へ配置します。含めるのは公開してよいクライアントIDとURLなどです。パスワードとトークンは含めません。ARNやURLの手作業での転記は不要です。

## 準備と実行

Python 3.14、uv、Terraform 1.12以上2.0未満、AWS CLI v2を用意します。AWSプロファイルの既定値は `develop`、リージョンは `ap-northeast-1` です。変更する場合は `terraform/providers.tf` の変数か `terraform/terraform.tfvars` で指定します。ログイン先のプロファイルも合わせてください。

配置する主体にはCognito・S3・CloudFrontの管理権限が必要です。ユーザーの作成には `cognito-idp:AdminCreateUser` と `cognito-idp:AdminSetUserPassword` が必要です。

実行コマンドは [commands.sh](commands.sh) にまとめています。サンプルのルートをカレントディレクトリにし、順に実行してください。WindowsはPowerShell、macOSはターミナルに1行ずつ貼り付けられます。

デプロイ後、`reader` ユーザーを作ります。パスワードは12文字以上で英大文字・英小文字・数字・記号を含めます。入力内容は表示せず、Terraformのステートにも保存しません。ユーザー作成は初回だけです。パスワード設定に失敗した場合はCognitoコンソールでそのユーザーのパスワードを再設定します。

## ブラウザで確認する

1. Terraformが出力するURLを開きます。
2. 「ログイン」を押し、Cognitoのホストされたログイン画面で `reader` とパスワードを入力します。
3. 元の画面に戻ると、IDトークンとアクセストークンのクレームが表示されます。
4. IDトークンとアクセストークンの `token_use`、`aud`／`client_id`、`scope`、`exp` を比較します。
5. 少し時間をおいて「トークンを更新」を押し、`iat`・`exp` を比較します。
6. 「ログアウト」でCognitoのログインセッションを終了し、未ログインの画面に戻ることを確認します。

認可コードは `state` を確認してから、PKCEの `code_verifier` とともにトークンへ交換します。トークンはブラウザのメモリに保持し、ページを再読み込みすると失われます。`sessionStorage` に一時保存するのはログイン要求のstate・nonce・PKCE verifierです。

画面のJWT表示はデコード結果です。署名・期限・発行元などの検証は、次のローカルPythonデモで確認します。

## Pythonでトークンを確認する

commands.shの `tokens` コマンドは次を順に実行します。AWSへの管理用ログインと、ユーザープールへの `reader` のログインは別の処理です。

| 手順 | API・処理 | 確認すること |
|---|---|---|
| 1 | `initiate_auth(USER_PASSWORD_AUTH)` | ユーザー名・パスワードで3種類のトークンを取得 |
| 2 | JWKS＋PyJWT、`get_user` | JWTの検証と、アクセストークンによる本人情報の取得 |
| 3 | `initiate_auth(REFRESH_TOKEN_AUTH)` | パスワードを再送せずID・アクセストークンを更新 |
| 4 | `revoke_token` | 今回のリフレッシュトークンを失効 |
| 5 | 再度 `REFRESH_TOKEN_AUTH` | `NotAuthorizedException` で更新が拒否されることを確認 |

トークン文字列は表示・ファイル保存せず、検証済みのクレームと有効期間を表示します。IDトークンはログインしたユーザーについての情報、アクセストークンはAPIへのアクセス、リフレッシュトークンは新しいトークンの取得に使います。リフレッシュトークンは不透明な文字列なのでJWTとしてデコードしません。

Python側ではJWKSの鍵を使い、署名、`iss`、`exp`、`token_use`、IDトークンの `aud`、アクセストークンの `client_id` を検証します。ブラウザの表示との違いも確認してください。

このPython用クライアントで発行するアクセストークンのscopeは `aws.cognito.signin.user.admin` です。ブラウザでは認可コードフローで要求した `openid` がscopeに含まれます。CognitoのAPI認証とOAuth認可コードフローの違いを確認できます。[CognitoのOAuthフロー](https://docs.aws.amazon.com/cognito/latest/developerguide/federation-endpoints-oauth-grants.html)

トークン失効は、署名そのものを無効にする処理ではありません。JWTをローカルで署名・期限検証するだけでは失効を検出できません。このデモでは、失効後のトークン更新がCognitoに拒否されることを確認します。ブラウザのログアウトはログインCookieと画面内のトークンを破棄する操作であり、発行済みトークンの一括失効とは別です。[トークン失効の仕様](https://docs.aws.amazon.com/cognito/latest/developerguide/token-revocation.html)

## 更新・片付け

HTML・JavaScriptはplan・applyで更新します。CloudFrontの反映中は少し待って再読み込みしてください。

commands.sh末尾の片付け手順で削除します。ユーザープール内の `reader` も削除されます。S3へ手動で追加したファイルがあるとバケット削除に失敗するため、追加したファイルは別途取り除いてください。ステートは削除完了まで保持します。

## 参考

- [Cognitoの認可エンドポイントとPKCE](https://docs.aws.amazon.com/cognito/latest/developerguide/authorization-endpoint.html)
- [トークンエンドポイント](https://docs.aws.amazon.com/cognito/latest/developerguide/token-endpoint.html)
- [boto3のinitiate_auth](https://docs.aws.amazon.com/boto3/latest/reference/services/cognito-idp/client/initiate_auth.html)
