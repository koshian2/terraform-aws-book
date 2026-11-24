# KMS署名によるPrivate Key JWTでアプリを認証する

OBOとclient_credentialsという「誰の権限で呼ぶか」は維持し、トークン取得時の「アプリ自身の認証」をPrivate Key JWTにします。AgentCore IdentityがKMSの非対称鍵でクライアントアサーションに署名し、Entraは登録済み公開証明書で検証します。秘密鍵はKMSから出ません。

OBOでは本人の`/me`、M2Mではアプリ権限による`/organization`を呼びます。M2Mターゲットも入口は利用者認証付きですが、下流のGraphに利用者の委任権限は使いません。GatewayのCustom OAuthプロバイダーを2個使い、Runtimeやローカル中継サーバーは使いません。

## 構成

```text
PythonでEntraへPKCEログイン → Gateway → AgentCore Identity（KMS署名のクライアント認証）→ Microsoft Graph
OBO: /me　／　client_credentials: /organization
```

`terraform/`がAWSなどのリソース定義、`scripts/`が準備・接続確認、`codex/`と`claude-code/`がエージェントの起動先です。KMS鍵は`terraform/keys/`の別stateで管理します。

## 事前準備

Python 3.14、uv、Terraform 1.14以降、AWS CLIを用意します。AWSプロファイルの既定値は`develop`、リージョンは東京です。WindowsではGit Bash、macOSではターミナルから実行します。uv・Terraform・AWS CLIを同じシェルのPATHから呼べるようにしてください。

[Entraと証明書の準備](entra-setup.md)に従い、このサンプル専用の中間APIとM2Mアプリを用意します。ログイン用の公開クライアントは新規作成するか、前のOBOサンプルの`entra-graph-obo-client`を再利用します。再利用時は、同手順の「既存の公開クライアントを再利用する場合」に従って今回の中間APIへのアクセス許可と管理者同意を追加します。

`terraform/keys/terraform.tfvars`に証明書作成者のIAM ARNを、`terraform/terraform.tfvars`にEntraの公開IDを設定します。`commands.sh`は鍵のapply後に証明書を生成し、Entraへの登録が終わるまで入力待ちします。`key_arns`とSHA-256サムプリントは`certificates.auto.tfvars.json`へ自動保存します。

KMS鍵の手動作成は不要です。ARNには既存の実行者を指定します。アプリIDの選び方、証明書の登録操作、KMSエイリアス重複やログインタイムアウトへの対処は、[構築手順](entra-setup.md)にまとめています。

証明書は既定90日です。再実行時は同じ鍵の有効な証明書を再利用し、鍵が違う場合や期限切れの場合は停止します。更新するときは新証明書の生成・Entra登録・プロバイダーのサムプリント更新・動作確認・旧証明書削除の順で行います。

## 実行と確認

コマンドは[commands.sh](commands.sh)にまとめています。このサンプルのルートで実行してください。設定ファイルがない場合は雛形を作って停止します。値を編集してから再実行します。AWSへのログインが必要な場合は先頭のSSOログイン行を有効にします。

`m2m_a`と`obo_a`がpassedになります。2ユーザー実行ではOBOの本人一致と、M2Mの組織情報がA→B→Aで変わらないことを確認します。`enable_obo=false`の場合、OBOはnot_runです。

Pythonクライアントは既定ではトークンやプロフィールを保存せず、`--report`で判定結果だけを`results/`へ保存します。未実施のケースは`not_run`です。すべての異常系を検証したという意味ではありません。

Entraへのログインはプライベートウィンドウで開きます。WindowsではEdgeのInPrivate（未インストールならChromeのシークレット）、macOSではChromeのシークレット（未インストールならEdgeのInPrivate）を使用します。Pythonの検証とエージェントのランチャーの両方に適用されます。利用者を切り替える際は、同じブラウザのプライベートウィンドウ間でログイン状態が共有されるため、既存のプライベートウィンドウをすべて閉じてからログインしてください。

コーディングエージェントは`launch_agent.py`から起動します。Entraでログインし、Bearerトークンを子プロセスの環境変数だけに渡します。生成設定には環境変数名だけを保存します。別のターミナルから直接起動するとトークンは引き継がれません。期限切れや利用者変更時はエージェントを終了し、ランチャーでログインし直します。MCP側で追加のOAuthログインを行う方式ではありません。

サンプルプロンプト:

> agentcore-private-key-jwtを使って、私のプロフィールと組織情報を確認し、それぞれ何が取得できたかをまとめてください。

## 後片付け

`commands.sh`末尾のコメントアウトした削除コマンドを使用します。Gateway側を先に削除し、最後にKMS鍵を削除予約します。KMSは7日間の待機後に削除されます。Entraの専用アプリ・証明書・検証ユーザーとローカルの公開証明書も片付けます。

AWSおよび外部サービスの利用料金・契約条件を確認し、利用後は必要な範囲を片付けてください。
