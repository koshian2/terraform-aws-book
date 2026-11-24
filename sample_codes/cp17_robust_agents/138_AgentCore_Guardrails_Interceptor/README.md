# Response InterceptorでMCPの応答中のメールをマスクする

問い合わせ取得ツールが返す文章を、AgentCore GatewayのResponse Interceptorで検査・加工します。InterceptorのLambdaがBedrock Guardrailsを呼び出し、メールアドレスを`{EMAIL}`に置き換えて返します。

```text
Python / Codex / Claude Code → Cognitoでログイン（認可コード＋PKCE）
  → JWT → Gateway → IAM SigV4 → Runtime / get_inquiry
  ← 元の問い合わせデータ
  → Response Interceptor Lambda → ApplyGuardrail（OUTPUT、EMAIL=ANONYMIZE）
  ← マスク済み文章からMCP応答を再構築
  ← Gatewayからクライアントへ返却
```

## 比較する結果

データは架空の問い合わせ3件です。Runtimeは元のデータを取得し、マスクはGatewayのLambdaが担当します。

| ID | 元の文章 | 期待する返却本文 |
| --- | --- | --- |
| T001 | 商品が届きません。連絡先は tanaka@example.com です。 | 商品が届きません。連絡先は {EMAIL} です。 |
| T002 | 商品の交換を希望します。連絡先は suzuki@example.com です。 | 商品の交換を希望します。連絡先は {EMAIL} です。 |
| T003 | 領収書の発行方法を教えてください。 | 変更せず返す |

メール検出時も正常なツール結果を返します。拒否して結果全体を隠す制御とは異なります。GuardrailはDRAFTを使い、設定の更新はその後の検査に反映されます。

MCPの`content`と`structuredContent`には同じデータが入る場合があるため、片方だけをマスクすると元のメールが残ります。この例ではマスク済みデータから両方を作り直し、元データを含み得る追加メタデータも引き継ぎません。ツール一覧の取得などはそのまま通します。

Guardrailsの障害・不明な問い合わせID・想定外の応答形式では、元データを返さず、本文を含まないMCPエラーを返します。このInterceptorはこの問い合わせスキーマ専用です。任意のMCPツールにそのまま適用できる汎用マスク処理ではありません。

## 実装

| ファイル | 役割 |
| --- | --- |
| `app/server.py` | Runtimeで問い合わせ取得MCPを公開 |
| `app/interceptor.py` | Guardrailの呼び出しと応答再構築 |
| `terraform/guardrail.tf` | EMAILのANONYMIZE設定 |
| `terraform/interceptor.tf` | Lambdaと専用IAMロール・ログ |
| `terraform/gateway.tf` | RESPONSE Interceptor、JWT認証、Runtime直接呼び出し拒否 |
| `terraform/cognito.tf`・`main.tf`・`iam.tf` | Cognito、Runtime、コード用S3、IAM |
| `scripts/build.py` | RuntimeとInterceptorのZIP作成 |
| `scripts/client.py`・`connection.py` | 3件の比較と、両表現に元メールが残らないことの確認 |

Guardrailsの呼び出し権限はInterceptorの実行ロールに付与します。GatewayロールがInterceptorを呼び出し、RuntimeにはGatewayロールからだけアクセスできるようにします。受信AuthorizationヘッダーはInterceptorに渡さず、イベント全体や検出したメールをLambdaログに出しません。

## 準備とデプロイ

Python 3.14、uv、Terraform 1.12以上2.0未満、AWS CLIを使います。AWS Providerは6.66.0、FastMCPは4.1.1です。コマンドは[commands.sh](commands.sh)にまとめています。サンプル直下でセクションごとに実行してください。

プロファイルは`develop`、リージョンは東京が既定です。変更は`terraform/terraform.tfvars`で行います。同時に複数デプロイする場合は`name`も変えます。デプロイにはS3・IAM・Cognito・AgentCore・Lambda・Guardrails・ログの管理権限と`iam:PassRole`が必要です。ユーザー作成にはCognitoの管理操作、後片付けにはRuntimeのログ・Workload Identity削除権限も必要です。初回のサービス連携ロール作成には`iam:CreateServiceLinkedRole`が必要になる場合があります。

Runtimeのターゲット登録前に、Gatewayの権限とRuntimeのリソースポリシー設定後60秒待機します。権限の反映完了を保証する待ち時間ではありません。

ZIPを先にビルドしてTerraformでデプロイします。コードや依存パッケージを変えたら再ビルド・再applyします。ターゲット登録がAuthorization errorになった場合は、権限と状態を確認し、commands.shの再同期セクションを使います。READYを確認してから失敗フラグを解除してください。

## Pythonとコーディングエージェントから試す

ユーザー`reader`を作成してPythonクライアントを実行します。ブラウザでCognitoにログインすると、1回のログインで3件を比較します。ブラウザとPythonは同じPCで使い、ログイン用の8765番ポートを空けてください。トークンはメモリだけに保持し、結果を`results/`に保存します。架空データ用の検証クライアントなので、確認に失敗した場合も受信結果を記録します。実際の個人情報を投入する用途では記録内容を別途絞ってください。

Codexは`configure_codex.py`で`codex/.codex/config.toml`を生成し、`codex/`をプロジェクトとして開きます。初回の`redirect_mismatch`では、表示された認可URLの`redirect_uri`をURLデコードして、`terraform/terraform.tfvars`の`codex_oauth_callback_url`に完全一致で設定します。`localhost`と`127.0.0.1`、末尾のコールバックIDを区別し、再apply・設定再生成後にログインします。

Claude Codeは`configure_claude.py`で`claude-code/.mcp.json`を生成し、そのフォルダで起動します。`/mcp`から`agentcore-inquiries`を選んで認証します。コールバックは8767番です。MCP通信はGatewayに直接接続します。

依頼例：

> agentcore-inquiriesを使って、問い合わせT001とT003の内容を表示してください。

T001では`{EMAIL}`への置換、T003では文章が変わらないことを確認します。Pythonクライアントは返却本文とMCPの両表現を確認し、期待と異なる場合は非0で終了します。

## 後片付け

後片付けコマンドはcommands.sh末尾にあります。削除前に対象を記録し、Terraformで専用リソースを削除した後、自動生成されたRuntimeログとWorkload Identityも削除します。LambdaログとCognitoユーザーも専用リソースとともに削除されます。

- [Response Interceptorの入出力](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-interceptors-types.html)
- [Interceptorの設定](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-interceptors-configuration.html)
- [ApplyGuardrail](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ApplyGuardrail.html)
