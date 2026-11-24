# Entraの準備

同じEntraテナントで、アプリ登録と管理者同意を行えるアカウントを用意します。検証ユーザーA・Bを作成し、初回パスワード変更・必要なMFA登録を済ませます。既存ユーザーを使う場合は削除対象から外してください。

## アプリ名とterraform.tfvarsの対応

各アプリの「概要」にある**アプリケーション（クライアント）ID**を入力します。アプリ名は以下を例とし、オブジェクトIDやシークレットの値は入力しません。

| アプリ名の例 | 役割 | terraform.tfvarsの項目 |
|---|---|---|
| `entra-graph-pkjwt-api` | OBOの中間API | `api_client_id` |
| `entra-graph-pkjwt-m2m` | アプリ権限でGraphを呼び出す | `m2m_client_id` |
| `entra-graph-obo-client`（前のOBOサンプルから再利用）または新規の`entra-graph-pkjwt-client` | Pythonで利用者がログインする公開クライアント | `local_client_id` |

**前のOBOサンプルの`entra-graph-obo-client`を再利用する場合、`local_client_id`は前のサンプルと同じ値です。** 以下の中間APIを準備した後、「既存の公開クライアントを再利用する場合」に進んでください。

## 中間APIアプリ

1. アプリの登録でシングルテナントの中間APIアプリを作ります。リダイレクトURIは不要です。クライアントIDを控えます。
2. 所有者に操作する管理者を登録します。
3. 「APIの公開」で`api://<中間APIのクライアントID>`を設定し、管理者同意のスコープ`access_as_user`を公開します。
4. Microsoft Graphの**委任されたアクセス許可**`User.Read`を追加し、管理者同意を付与します。OBOの交換中は同意画面を出せないため、事前に同意を用意します。
5. マニフェストの`api.requestedAccessTokenVersion`を`2`に設定します。

## ローカル公開クライアント

### 既存の公開クライアントを再利用する場合

1. Entraの「アプリの登録」で、前のOBOサンプルの`entra-graph-obo-client`を開きます。
2. 「概要」の**アプリケーション（クライアント）ID**を、今回の`terraform/terraform.tfvars`の`local_client_id`に入力します。
3. 「認証」で、デスクトップ用のリダイレクトURIに`http://localhost`が登録されていることを確認します。
4. 「APIのアクセス許可 → アクセス許可の追加 → 自分のAPI」から、今回作成した`entra-graph-pkjwt-api`を選び、`access_as_user`を追加します。
5. 「管理者の同意を与えます」を実行し、追加したアクセス許可に同意済みであることを確認します。既に追加・同意済みなら再設定は不要です。

前の中間APIへの許可は残したままで構いません。公開クライアントにシークレットや証明書を追加する必要はありません。共有する公開クライアントは後片付け時に削除しません。

### 新しく公開クライアントを作る場合

1. 新規のシングルテナントアプリ（例：`entra-graph-pkjwt-client`）を登録し、所有者に管理者を登録します。このアプリのクライアントIDを`local_client_id`に設定します。
2. 認証の「モバイル アプリケーションとデスクトップ アプリケーション」で`http://localhost`を登録します。PythonのMSALがログインを受け取ります。
3. APIのアクセス許可で、自分のAPIから中間APIの`access_as_user`を追加し、管理者同意を付与します。
4. 公開クライアントのためシークレットや証明書は登録しません。

同意は中間API→Graphと、公開クライアント→中間APIの2か所です。IDにはアプリのオブジェクトIDではなくアプリケーション（クライアント）IDを使います。

## M2M用アプリ

もう1つシングルテナントアプリを登録します。Microsoft Graphの**アプリケーションの許可**`Organization.Read.All`を追加して管理者同意を付与します。既定で追加された委任権限`User.Read`は削除します。リダイレクトURI・API公開・Client Secretは不要です。

## KMSと証明書

KMS鍵は`commands.sh`の前半で作成されるため、事前に手動作成する必要はありません。先に入力するのは、鍵で証明書に署名する**既存の実行者**のARNです。

1. `terraform/keys/terraform.tfvars`の`certificate_signer_arn`に、AWSプロファイルで使用するIAMロールまたはIAMユーザーのARNを設定します。新しいロールを作る指定でも、後で作られるGatewayロールの指定でもありません。
2. SSOの場合は、IAMのロール一覧で使用中のSSOロールを開き、パスを含む完全なIAMロールARNをコピーします。`arn:aws:iam::...:role/...`を使い、ログイン後の呼び出し元情報に出る`arn:aws:sts::...:assumed-role/...`は使いません。
3. 中間APIとM2MアプリにはClient Secretを作成せず、`commands.sh`を実行します。KMS鍵の作成後、公開証明書が生成され、Entraへの登録待ちで停止します。
4. 以下の対応で、Entraの「アプリの登録」から対象アプリを開きます。

| 登録先アプリ | アップロードする公開証明書 |
|---|---|
| `entra-graph-pkjwt-api` | 今回生成された`obo.cer` |
| `entra-graph-pkjwt-m2m` | 今回生成された`m2m.cer` |

5. 各アプリの「証明書とシークレット → 証明書 → 証明書のアップロード」で対応するファイルを選び、「追加」を押します。
6. 両方のアプリで証明書が一覧に表示され、有効期間内であることを確認してから、待機中のシェルでEnterを押します。続いてGatewayなどが作成されます。

ログイン用の公開クライアントには証明書を登録しません。以前の証明書がEntraに残っていても、KMS鍵を作り直した場合は今回の鍵から生成した証明書を登録する必要があります。ファイル名が同じでも、鍵が違えば互換性はありません。

AgentCoreに渡す`x5t#S256`はスクリプトが計算するDER証明書のSHA-256をbase64url化した値です。Entra画面に表示されたサムプリントをそのまま転記しません。証明書自体への署名はSHA-256/RSA PKCS#1 v1.5、OAuthのクライアントアサーションへの署名はPS256です。

OBOの`assertion`は利用者トークン、`client_assertion`はアプリ認証用のKMS署名JWTです。OBOターゲットには`requested_token_use=on_behalf_of`も設定します。入口の公開クライアント、中間API、M2Mアプリの3つを取り違えないでください。

## 構築・確認で止まったとき

### KMSエイリアスが既に存在する

```text
AlreadyExistsException: An alias with the name ... already exists
```

同じAWSアカウント・リージョンに、同名のエイリアスが残っています。この段階では、新しい鍵本体だけは作成済みの場合があります。Terraformのstateを削除してやり直さず、既存エイリアスの参照先と管理元を確認してください。

以前の環境が不要なら、その環境を管理するTerraformで鍵とエイリアスを削除してから再実行します。残す必要がある場合は、今回のエイリアスを別名にします。エイリアスは鍵本体とは別に削除できるため、旧鍵の削除待機期間が終わるまで名前の再利用を待つ必要はありません。本サンプルの鍵本体は7日後の削除予約です。詳細は[AWSのエイリアス削除](https://docs.aws.amazon.com/kms/latest/developerguide/alias-delete.html)と[鍵の削除](https://docs.aws.amazon.com/kms/latest/developerguide/deleting-keys.html)を参照してください。

エイリアスの削除で次のエラーになる場合は、IAM管理者権限だけでなく、参照先のキーポリシーも確認します。

```text
AccessDeniedException: ... no resource-based policy allows the kms:DeleteAlias action
```

削除する実行者に対し、対象のエイリアスと参照先の鍵について`kms:DeleteAlias`が許可されるようにします。鍵の管理用ポリシーが`kms:Create*`や`kms:Update*`を許可していても、`kms:DeleteAlias`は含まれません。詳細は[DeleteAliasの権限要件](https://docs.aws.amazon.com/kms/latest/APIReference/API_DeleteAlias.html)を参照してください。

### ログイン待ちでタイムアウトする

```text
BrowserInteractionTimeoutError
```

ブラウザでのログインが5分以内に完了せず、まだGraphの呼び出しに進んでいない状態です。開いたプライベートウィンドウで、Entraに用意した検証ユーザーのサインイン名とパスワードを入力し、必要なMFAや同意まで完了してください。Client IDやアプリ名でログインするのではありません。

構築が完了していれば、`commands.sh`にある`client.py --report`の検証コマンドだけを再実行できます。Terraformの適用や証明書登録をやり直す必要はありません。別ユーザーに切り替える場合は、既存のプライベートウィンドウをすべて閉じてください。

### Aだけの検証とA→B→Aの検証を区別する

通常実行は検証ユーザーAだけです。2ユーザーで確かめるには、`commands.sh`のコメント内にある`--two-users --negative --report`付きのコマンドを実行します。Aでログインした後、Bのログインでは別の検証ユーザーを選びます。最後のAへの呼び出しは、保持しているAのトークンを使って自動実行されます。

| 結果の項目 | 確認していること |
|---|---|
| `obo_a_b_a: passed` | A→B→Aで、それぞれ本人のプロフィールと一致する |
| `m2m_a_b_a: passed` | 利用者が変わっても、同じ組織情報を取得する |
| `no_token`・`malformed_token`・`tampered_signature` | 入口の不正な認証要求を拒否する |

`partial_success_remaining_checks_not_run`は、証明書削除やKMS鍵無効化などの追加検証が未実施という意味です。実施した検証の成否は`checks`と`rejections`で確認します。`--negative`を付けても、これらの証明書・鍵の異常系まですべて検証されるわけではありません。
