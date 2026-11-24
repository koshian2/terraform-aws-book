# RuntimeのIAMロールでInfisicalへ認証する

Runtimeの一時的なAWS資格情報でSTS GetCallerIdentity要求に署名し、その署名済み要求をInfisicalに渡します。InfisicalがAWSの身元を検証して短命トークンを発行し、専用Machine Identityに許可したプロジェクトの値を取得します。外部接続用の固定アクセストークンをRuntimeに配置する必要がありません。

本例のworkload identityは「実行環境の身元」という意味です。外向きの認証にAgentCore IdentityのOAuthプロバイダーを使う例ではありません。Cognitoの利用者が変わっても、Infisicalには同じRuntimeの身元でアクセスします。

## 構成

```text
Codex / Claude Code / Python → Cognito認証付きGateway → IAM認証のRuntime MCP → Infisical AWS Auth → Secret取得
```

`terraform/`がAWSなどのリソース定義、`scripts/`が準備・接続確認、`codex/`と`claude-code/`がエージェントの起動先です。実行コードは`app/`にまとめています。

## 事前準備

Python 3.14、uv、Terraform 1.14以降、AWS CLIを用意します。AWSプロファイルの既定値は`develop`、リージョンは東京です。WindowsではGit Bash、macOSではターミナルから実行します。uv・Terraform・AWS CLIを同じシェルのPATHから呼び出せるようにしてください。

1. Infisical Cloudの組織と、管理操作できるアカウントを用意します。`infisical_host`は利用するリージョンのURLに合わせます。
2. Terraform管理用のMachine Identityを作成し、この検証専用の組織管理権限を与えます。Runtime用Identityとは別です。
3. 管理用IdentityのAWS Authを有効にし、Allowed Principal ARNsをTerraform実行者に限定します。ロールの場合は`arn:aws:iam::<アカウントID>:role/<ロール名>`の形式で、IAMパスとSTSのセッション名を含めません。SSOのロールも`role/AWSReservedSSO_...`の形式にします。Allowed Account IDsは空欄にし、アカウント全体やワイルドカードを許可しません。Universal Authが初期設定されている場合は外し、管理用の固定Client Secretは作成しません。
4. STS endpointを利用リージョンに設定し、組織ID・管理用Identity IDを控えます。
5. `terraform/terraform.tfvars`に3項目を記入します。InfisicalプロバイダーはAWSプロバイダーとは別にAWS資格情報を取得するため、`commands.sh`の`AWS_PROFILE`も実行者に合わせます。

TerraformがRuntime専用Machine Identity、AWS Auth、プロジェクト、viewer権限、デモ用`DEMO_MESSAGE`を作成します。Runtime用AWS AuthはRuntimeのIAMロールだけを許可し、トークンの有効期間を300秒にします。デモ値は公開してよい文字列です。管理用Identityや実際のシークレットをRuntimeに渡しません。

## 実行と確認

コマンドは[commands.sh](commands.sh)にまとめています。このサンプルのルートで実行してください。設定ファイルがない場合は雛形を作って停止します。値を編集してから再実行します。AWSへのログインが必要な場合は先頭のSSOログイン行を有効にします。

`status: ok`と`Hello from Infisical`が返ります。トークンやAWS資格情報は返しません。

Codexは`codex/`、Claude Codeは`claude-code/`で起動します。生成された設定ファイルのMCPにログインするときは、シェルに表示されたCognitoの`reader`と設定したパスワードを使います。CodexのコールバックはURLから計算してTerraformに保存し、ログイン画面への到達を確認します。Claude Codeは`/mcp`から認証します。利用者を切り替える場合はMCPの認証を解除し、Cognitoのブラウザセッションからもログアウトして再認証してください。

サンプルプロンプト:

> agentcore-infisicalを使ってデモメッセージを取得してください。

## 後片付け

`commands.sh`末尾のコメントアウトした削除コマンドを使用します。先にTerraformでRuntime用Identityとプロジェクトを削除し、その後に手動作成した管理用IdentityをInfisicalで削除します。先に管理用Identityを削除するとTerraformから削除できなくなります。

AWSおよび外部サービスの利用料金・契約条件を確認し、利用後は必要な範囲で後片付けを行ってください。

Runtimeが自動作成するCloudWatch LogsのロググループはTerraformの管理対象外です。削除前に`runtime_log_group`出力の名前を控え、不要になったログは別途削除してください。
