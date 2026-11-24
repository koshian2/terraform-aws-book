# Entraの利用者の権限をGraphへ引き継ぐ（OBO）

利用者が中間API向けに取得したトークンをGatewayが検証し、AgentCore IdentityがMicrosoft Graph向けのトークンに交換します。Graphの`/me`が返すユーザーIDを、署名検証した入口トークンの`oid`と照合します。入口トークンをそのままGraphに転送する構成ではありません。

GatewayのMicrosoft OAuthプロバイダーは、Secrets Managerの`clientSecret`を外部参照します。Terraformはシークレットのメタデータだけを取得し、秘密値をstateに読み込みません。Runtimeやローカル中継サーバーは使いません。

## 構成

```text
PythonでEntraへPKCEログイン → Gateway → AgentCore Identity（OBO）→ Microsoft Graph /me
```

`terraform/`がAWSなどのリソース定義、`scripts/`が準備・接続確認、`codex/`と`claude-code/`がエージェントの起動先です。

## 事前準備

Python 3.14、uv、Terraform 1.14以降、AWS CLIを用意します。AWSプロファイルの既定値は`develop`、リージョンは東京です。WindowsではGit Bash、macOSではターミナルから実行します。uv・Terraform・AWS CLIを同じシェルのPATHから呼び出せるようにしてください。

[Entraの準備](entra-setup.md)に従い、中間APIとローカル公開クライアントの2つのアプリ、検証ユーザー2人、Secrets Managerの専用シークレットを準備します。

`terraform/terraform.tfvars.example`をコピーし、テナントID・アプリID・シークレット名を設定します。`secret_name`はこのサンプルと同じリージョンのシークレットを指定します。Entraのシークレットの値やトークンはtfvarsに記入しません。

## 実行と確認

コマンドは[commands.sh](commands.sh)にまとめています。このサンプルのルートで実行してください。設定ファイルがない場合は雛形を作って停止します。値を編集してから再実行します。AWSへのログインが必要な場合は先頭のSSOログイン行を有効にします。

`gateway_user_a`がpassedになり、2ユーザー実行では`gateway_user_b`と`a_b_a_isolation`もpassedになります。ログイン時はA、Bの順に別ユーザーを選びます。保持したAのトークンでも再度Aを取得できることを確認します。

Entraのログインはプライベートウィンドウで開きます。WindowsではEdge（なければChrome）、macOSではChrome（なければEdge）を使うため、いずれかをインストールしてください。Pythonの検証とエージェントのランチャーに共通です。同じブラウザのプライベートウィンドウ間ではセッションが共有されることがあるため、前回のログインを引き継ぎたくない場合は既存のプライベートウィンドウをすべて閉じてから実行します。

Pythonクライアントは既定ではトークンやプロフィールを保存せず、`--report`で判定結果だけを`results/`に保存します。未実施のケースは`not_run`です。すべての異常系を検証したという意味ではありません。

コーディングエージェントは`launch_agent.py`から起動します。Entraでログインし、Bearerトークンを子プロセスの環境変数だけに渡します。生成された設定ファイルには環境変数名だけを保存します。別のターミナルから直接起動するとトークンは引き継がれません。期限切れや利用者変更時はエージェントを終了し、ランチャーでログインし直します。MCP側で追加のOAuthログインを行う方式ではありません。

サンプルプロンプト:

> agentcore-entra-oboを使って、ログインしている私のプロフィールを確認してください。

## 後片付け

`commands.sh`末尾のコメントアウトした削除コマンドを使用します。手動で準備したEntraのアプリ・検証ユーザーとSecrets ManagerのシークレットはTerraformの削除対象ではありません。このサンプル専用のものを各コンソールで削除してください。

AWSおよび外部サービスの利用料金・契約条件を確認し、利用後は必要な範囲で後片付けを行ってください。
