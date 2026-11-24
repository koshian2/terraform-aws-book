# 利用者の同意を得てGitHubへ接続する（3LO）

GitHub Appのユーザーアクセストークンを利用します。151節のインストールトークンとは異なり、Appに与えた権限と、同意したGitHubユーザーの権限の範囲でアクセスします。Cognitoは入口の本人確認、AgentCore Identityは外部トークンの管理、同意ポータルは利用者による接続・同意を担当します。GatewayのOpenAPIターゲットからGitHubへ接続し、Runtimeやローカル中継サーバーは使いません。

`app/portal_handler.py`はCloudFormationカスタムリソースの管理用Lambdaです。ポータル作成後に決まるURLをCognitoへ登録するために使い、利用者の同意要求自体はAWSのマネージドポータルが処理します。

## 構成

```text
Codex / Claude Code / Python → Cognito認証付きGateway → AgentCore Identity → GitHub Issues
利用者 → マネージド同意ポータル → GitHubの同意画面
```

`terraform/`がAWSなどのリソース定義、`scripts/`が準備・接続確認、`codex/`と`claude-code/`がエージェントの起動先です。実行コードは`app/`にまとめています。

## 事前準備

Python 3.14、uv、Terraform 1.14以降、AWS CLIを用意します。AWSプロファイルの既定値は`develop`、リージョンは東京です。WindowsではGit Bash、macOSではターミナルから実行します。uv・Terraform・AWS CLIを同じシェルのPATHから呼べるようにしてください。

1. GitHubに検証用リポジトリとIssueを用意し、専用GitHub Appを作成します。IssuesはRead-only、Webhookは無効にします。必要なリポジトリへインストールし、検証ユーザーにもそのリポジトリを閲覧する権限を与えます。
2. AppのCallback URLは、最初は説明用の仮URL（`https://example.com/callback`など）を登録します。AWS作成後、スクリプトが表示するAgentCore Identityの`github_callback`に置き換えます。Cognitoのlocalhostコールバックとは別です。
3. AppのClient IDとClient Secretを用意します。秘密鍵のPEMではありません。ユーザートークンの期限設定はGitHub Appの設定に従います。
4. `terraform/terraform.tfvars`へ検証用`github_repository`を設定し、`commands.sh`を順に実行します。
5. 初回applyでポータルが作られ、`finalize.py`がポータル用CognitoクライアントIDをGatewayの許可対象へ反映します。
6. `setup_github.py`が示すCallback URLをAppへ登録してから、Client IDとSecretを入力します。秘密値はTerraformのephemeral/write-only入力へ渡します。
7. 表示された同意ポータルを開き、Cognitoの`reader`でログインしてGitHub接続に同意します。その後のMCP接続も同じCognitoユーザーを使います。

接続前にツールを呼ぶと、外部接続への同意を求めるエラーになることがあります。同意後に1回呼び直します。GitHubユーザーの閲覧権限やAppのインストール先が不足する場合は、同意しても読めません。

## 実行と確認

コマンドは[commands.sh](commands.sh)にまとめています。このサンプルのルートで実行してください。設定ファイルがない場合は雛形を作って停止します。値を編集してから再実行します。AWSへのログインが必要な場合は先頭のSSOログイン行を有効にします。

Cognitoユーザーに紐づいたGitHub接続でIssueの内容が返ります。同意前の要求、同意後の成功、リポジトリへの閲覧権限不足を区別します。

Codexは`codex/`、Claude Codeは`claude-code/`で起動します。生成設定のMCPへログインするときは、シェルに表示されたCognitoの`reader`と設定したパスワードを使います。CodexのコールバックはURLから計算してTerraformへ保存し、ログイン画面への到達を確認します。Claude Codeは`/mcp`から認証します。利用者を切り替える場合はMCPの認証を解除し、Cognitoのブラウザーセッションからもログアウトして再認証してください。

サンプルプロンプト:

> agentcore-github-consentを使って、私が接続したGitHubで設定されたリポジトリのIssue #1を確認してください。同意が必要なら、手順を案内してください。

## 後片付け

`commands.sh`末尾のコメントアウトした削除コマンドを使用します。ポータル、専用のOIDCプロバイダーとCognitoクライアントはCloudFormationの削除処理で片付けます。GitHub App、同意・インストール、検証用リポジトリはGitHub側で片付けます。

AWSおよび外部サービスの利用料金・契約条件を確認し、利用後は必要な範囲を片付けてください。
