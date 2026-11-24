# 演習（3） Knowledge Basesと短期記憶を使う料理相談

料理を探した後も「それ、どう作るんだっけ？」「切ったあとどうする？」と相談を続けるサンプルです。Runtime上の単一エージェントが会話履歴を読み、必要に応じてレシピを検索・再検索します。

```text
Codex / Claude Code → ローカルHTTP MCPプロキシ（IAM署名）
                              ↓ MCP
Python CLI ─── IAM署名 ──→ Runtime上のリモートMCP
                              ├─ 料理相談のツール定義・相談ID発行
                              └─ 単一エージェント
                                  ├─ Bedrock Converse：検索・再検索・回答の判断
                                  ├─ Knowledge Bases → S3 Vectors：レシピ原文
                                  └─ AgentCore Memory：相談ごとの会話履歴
```

## 各要素の担当

| 要素 | 担当 |
|---|---|
| Codex / Claude Code | 新規相談か続きかを選び、MCPツールに質問と相談IDを渡す |
| ローカルMCPプロキシ | AWS認証とMCP通信の中継。Runtimeのツール一覧を取得して代理公開する |
| RuntimeのMCPサーバー | ツールの名前・説明・引数を定義し、相談IDを発行して処理を実行する |
| Runtimeのエージェント | 履歴から指示語や条件を整理し、検索結果を比較して回答する |
| KB | 全利用者に共通する料理の材料・器具・手順を提供する |
| Memory | 今回選んだ料理や利用者が伝えた進捗を質問・回答の履歴として7日間保持する |

各回答の最初に原本検索を必須とし、検索文・料理ID・再検索の要否はRuntime側のモデルが決めます。Converseのtool useをPythonが処理し、検索結果をモデルに返します。検索は1回答につき4回、モデル呼び出しは6回までです。条件に合う資料がなければ条件変更を相談するよう指示しています。

## Runtimeが公開するMCPツール

| ツール | 役割 |
|---|---|
| `start_cooking_session` | IDを発行して新しい料理相談を開始 |
| `ask_cooking` | 指定した相談をMemoryから復元して継続 |
| `list_cooking_sessions` | 再開できる相談一覧を取得 |
| `get_cooking_history` | 保存済みの履歴を取得して進捗・保存結果を確認 |

定義は`app/runtime.py`だけに置きます。ローカル側では`tools/list`・`tools/call`を中継し、同じ定義を手書きで複製しません。CodexやClaude Codeからはツール名・説明・引数が見えます。KB検索などの内部処理はツールの返却結果で確認できます。

## ファイル構成

| パス | 内容 |
|---|---|
| `app/runtime.py` | リモートMCPのツール定義と実行、新規相談IDの発行 |
| `app/agent.py` | モデルのツール呼び出しとKB検索 |
| `app/memory.py` | 会話の保存・復元・セッション一覧 |
| `server.py` | ツール定義を持たないローカルHTTP MCPプロキシ |
| `scripts/connection.py` | リクエストごとのIAM署名とRuntimeへのMCP接続 |
| `scripts/` | CLI、Linux ARM64用ZIPの作成、削除後の後片付け |
| `terraform/` | Runtime、Memory、KB、S3 Vectors、S3、IAM |
| `data/recipes.json` | 自作の架空レシピ30件（主菜15件・副菜15件） |
| `codex/`・`claude-code/` | 各エージェントを起動するフォルダとMCP設定 |
| `commands.sh` | デプロイ・取り込み・実行・後片付けのコマンド |

レシピは教材用の創作で、調理検証済みではありません。肉・魚・豆腐・野菜、薄味・しっかり味、加熱あり・なしなどの候補を用意しています。料理IDはレシピの識別用です。

## 準備とデプロイ

Python 3.14、uv、Terraform 1.12以上、AWS CLIと、利用するCodexまたはClaude Codeを用意します。AWSプロファイルは`develop`、リージョンは`ap-northeast-1`、モデルは`jp.anthropic.claude-sonnet-4-6`です。Terraformの変数で変更できます。

実行コマンドは[commands.sh](commands.sh)にまとめています。サンプル直下でセクションごとに実行してください。WindowsはPowerShell、macOSはシェルで同じコマンドを使えます。ローカルMCPプロキシは8000番ポートを使用するため、同じポートを使う別サンプルは停止します。

TerraformのapplyでコードZIPのデプロイとレシピの配置を行った後、`sync`でKBに取り込みます。TerraformはJSONの各レシピを短いテキストとメタデータに変換してS3に配置し、KBはレシピ1件を分割せず取り込みます。料理の続きは`recipe_id`のメタデータフィルターで原本を検索できます。データ変更時もapplyとsyncを順に実行します。

デプロイに使う認証情報には各AWSリソースを管理する権限とIAMロールを渡す権限が必要です。ローカルクライアントはKBの取り込み操作とRuntime呼び出しを行います。Runtimeの専用ロールには、対象Memoryのイベント・一覧操作、対象KBの検索、指定モデルの呼び出し、コードの取得とログ出力を許可します。

## 料理相談を試す

ローカルMCPプロキシを起動し、Codexは`codex/`、Claude Codeは`claude-code/`で起動して接続を確認します。以下はどちらでも使えます。

> agentcore-cookingを使って、鶏肉とキャベツで作れる薄味の主菜を1品教えてください。出典も表示してください。

> agentcore-cookingで同じ相談を続けてください。それ、どう作るんだっけ？

> agentcore-cookingで続けてください。鶏肉とキャベツを切りました。このあとどうする？

曖昧な「切ったあと」だけで工程を断定せず、何を切ったか確認するよう指示しています。手順を説明しただけでは作業済みと扱いません。料理IDの引用は今回取得した資料にあるかコードでも検査します。ただし、モデルによる条件の読み取りや説明の正確さは、出典と照合して確認してください。

## 終了後に再開する

CodexやClaude Codeの会話を終了し、新しい会話を開始します。サーバーを再起動してもかまいません。

> agentcore-cookingで、以前の料理相談を再開したいです。どんな相談が残っていますか？

一覧から再開したい相談を選び、次のように依頼します。

> agentcore-cookingで、鶏肉とキャベツについての相談を再開してください。選んだ料理と、どこまで作業したと伝えたか教えてください。

リモートMCPの新規開始ツールがRuntime上でUUIDを発行し、後続の呼び出しではCodex／Claude CodeがそのIDを渡します。Memoryの`ListSessions`で10件ずつ取得し、各相談の最初の質問を表示名にします。`next_token`があれば次のページを取得できます。固定の`demo-cook`というactor IDを使うデモで、利用者ごとのアクセス分離は実装していません。

相談ID、MCP接続のセッション、Runtimeの実行セッションは別物です。プロキシは操作ごとにRuntimeに接続し直し、接続中はAWSが返したMCPセッションIDを引き継ぎます。料理の会話はプロセス内のキャッシュに依存せず、引数の相談IDを使ってMemoryから毎回復元します。存在しない相談IDでは新しい相談を勝手に作らず、`session_not_found`を返します。

## 結果の確認と制約

- `answer`：料理ID付きの回答。
- `sources`：今回検索したレシピ原文・料理ID・S3の場所。回答で採用していない候補も含みます。
- `search_trace`：実際の検索条件と取得した料理ID。モデル内部の思考ではありません。
- `restored_event_count`：Memoryから復元したイベント数。追加質問・再開では増えます。
- `results/`：Python CLIのリクエスト、回答、取り込み結果のローカル記録。プロキシは料理相談の結果保存を行いません。会話復元のキャッシュには使いません。

同じ相談への質問は順番に実行してください。並行更新のロックや、手動再送の重複排除は実装していません。取得する履歴は60,000文字を上限とし、超えた場合は新しい相談を案内します。新しい質問は2,000文字までです。

回答後に質問・回答・参照レシピIDを1つのイベントとして保存します。モデルの出力上限や検索処理などで失敗した場合は新しい会話を保存しません。保存失敗や通信切断が起きた場合は保存済みかどうかが未確定になることがあるため、自動再送せず`get_cooking_history`またはCLIの`history`で確認します。新規開始の応答を受け取れなかった場合はIDも不明になるため、まず相談一覧から該当する質問を探します。期限切れや削除済みの履歴から再開することはできません。

## 後片付け

`commands.sh`末尾の手順で削除対象のIDを記録してからTerraformの削除計画を適用し、自動生成された専用ログとWorkload Identityも削除します。Memoryの会話、KB、レシピ用S3、ベクトル、Runtimeのコードと専用IAMロールが削除対象です。

## 参考

- [Converseのツール呼び出し](https://docs.aws.amazon.com/bedrock/latest/userguide/tool-use-client-side.html)
- [Memoryの会話履歴取得](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/short-term-list-events.html)
- [Memoryのセッション一覧](https://docs.aws.amazon.com/bedrock-agentcore/latest/APIReference/API_ListSessions.html)

- [AgentCore RuntimeのMCPプロトコル](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-mcp-protocol-contract.html)
