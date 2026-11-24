# GitHub Appの権限でIssueを読む（M2M）

入口でログインするCognitoユーザーと、GitHubへアクセスする主体は別です。GitHub Appの秘密鍵でApp JWTを作り、インストールアクセストークンへ交換します。どのCognitoユーザーが呼んでも、同じAppのインストール権限で、設定した1リポジトリのIssueを読みます。Runtime内のMCPは読み取りツール1個を公開し、GatewayがリモートMCPとして提供します。ローカル中継サーバーは使いません。

## 構成

```text
Codex / Claude Code / Python → Cognito認証付きGateway → IAM認証のRuntime MCP → GitHub App → GitHub Issues
```

`terraform/`がAWSなどのリソース定義、`scripts/`が準備・接続確認、`codex/`と`claude-code/`がエージェントの起動先です。実行コードは`app/`にまとめています。

RuntimeのロググループはAWSの自動作成に任せ、Terraformでは重複して作成しません。デプロイ後に`cleanup.py configure`で保存期間を7日に設定します。

## 事前準備

Python 3.14、uv、Terraform 1.14以降、AWS CLIを用意します。AWSプロファイルの既定値は`develop`、リージョンは東京です。WindowsではGit Bash、macOSではターミナルから実行します。uv・Terraform・AWS CLIを同じシェルのPATHから呼べるようにしてください。

1. GitHubに検証用リポジトリを用意し、Issueを1件作成して番号を控えます。
2. GitHubのSettings → Developer settings → GitHub Appsで専用Appを登録します。名前は一意、Homepage URLは説明用URLを指定し、Webhookは無効にします。
3. Repository permissionsのIssuesをRead-onlyにします。Metadataの必須権限以外は追加しません。
4. Install Appで検証用リポジトリだけを選んでインストールします。
5. AppのClient IDと、Generate a private keyで取得したPEMファイルを用意します。PEMはこのサンプルの外で保管してください。OAuthのClient Secretはこの例では使いません。
6. `terraform/terraform.tfvars.example`をコピーして`terraform/terraform.tfvars`を作り、`github_repository`を変更します。

実行中の`setup_github.py`が秘密鍵を検査してインストールIDを取得し、Terraformのephemeral/write-only入力でSecrets Managerへ保存します。公開IDは`github.auto.tfvars.json`へ保存します。秘密鍵は引数・state・生成設定へ保存しません。

## 実行と確認

コマンドは[commands.sh](commands.sh)にまとめています。このサンプルのルートで実行してください。設定ファイルがない場合は雛形を作って停止します。値を編集してから再実行します。AWSへのログインが必要な場合は先頭のSSOログイン行を有効にします。

設定したIssueの内容が返り、`status`が`ok`になります。GitHub Appの権限で読むため、Cognitoユーザーを変えても下流の主体は変わりません。

Codexは`codex/`、Claude Codeは`claude-code/`で起動します。生成設定のMCPへログインするときは、シェルに表示されたCognitoの`reader`と設定したパスワードを使います。CodexのコールバックはURLから計算してTerraformへ保存し、ログイン画面への到達を確認します。Claude Codeは`/mcp`から認証します。利用者を切り替える場合はMCPの認証を解除し、Cognitoのブラウザーセッションからもログアウトして再認証してください。

サンプルプロンプト:

> agentcore-github-m2mを使って、設定されたリポジトリのIssue #1の内容を確認し、要点をまとめてください。

## 後片付け

`commands.sh`末尾のコメントアウトした削除コマンドを使用します。GitHub Appのインストール、App、ダウンロードした秘密鍵、検証用リポジトリはGitHub側とローカルで別途片付けます。

削除前の`cleanup.py capture`で対象を記録し、Terraformによる削除後の`cleanup.py leftovers`でRuntimeのログとRuntime・GatewayのWorkload Identityを削除します。

AWSおよび外部サービスの利用料金・契約条件を確認し、利用後は必要な範囲を片付けてください。
