# ツール層で操作・取得件数・返却項目を制限する

架空の購入履歴を検索する、ローカルHTTPのFastMCPサンプルです。SQLインジェクション対策を入れたうえで、LLMが呼び出せる操作を購入履歴の検索に限定します。AWSリソースやモデルの呼び出しはありません。

```text
Codex / Claude Code / 検証クライアント
    → HTTP MCP (127.0.0.1:8000/mcp)
    → 入力検証 → 固定SQL + パラメーターバインド → SQLite（読み取り専用接続）
    ← 購入ID・購入日・商品名・金額だけ返却
```

## 何を制限するか

| 対象 | 実装 | 確認する挙動 |
| --- | --- | --- |
| SQL構文への値の混入 | `?`によるパラメーターバインド | SQL風の商品名も文字列として検索し、全件検索に変わらない |
| 操作の自由度 | 購入履歴検索1つ、SQL・テーブル・列・順序を固定 | `sql`や`table`など未定義の引数は拒否 |
| 1回の取得件数 | 整数1〜10の検証とSQLの`LIMIT` | 1000件・負数・文字列・真偽値を拒否 |
| 返却する情報 | `SELECT`の列を明示 | 元データのメール・住所・社内メモは返さない |
| 期間 | 実在する日付、開始日≦終了日 | 不正日付や逆転した期間は拒否 |

SQLインジェクション対策は値をSQL構文として解釈させない対策です。それだけでは、正しいSQLによる過大取得や不要な列の公開を防げないため、業務操作と返却範囲もコードで固定します。商品名検索は大文字小文字を区別する部分一致で、SQL風の文字列をブラックリストで禁止していません。

本例は架空の1人分のデータを対象とし、認証やテナント分離は扱いません。サーバーはループバックに限定しています。10件という上限は1回の返却量の制限で、繰り返し取得やDB全体の処理時間を制限する仕組みではありません。タイムアウト、レート制限、認証情報に基づく行単位の認可は別途必要に応じて組み合わせます。

## 実行と接続

Python 3.14とuvを使います。コマンドは[commands.sh](commands.sh)に集約しています。WindowsではGit Bash、macOSではbashから実行してください。

1. `commands.sh`の`serve`を実行します（引数なしでも同じ）。初回に架空の15件をSQLiteに登録し、サーバーをフォアグラウンドで起動します。
2. 別ターミナルから同じファイルの`check`を実行します。LLMを介さず14ケースを直接送信し、各ケースの`PASS`と`results/`のJSONを確認します。
3. Codexは`codex/`、Claude Codeは`claude-code/`を作業ディレクトリとして起動します。各フォルダにHTTP MCPの設定を同梱しています。`/mcp`で`purchase-history`の接続を確認します。OAuthログインは不要です。
4. 終了時はサーバー側でCtrl+Cを押します。生成された`data/purchases.db`と`results/`はGit管理外です。初期データに戻す場合は停止後にDBファイルを削除し、再起動します。

ポート8000は他のローカルMCPサンプルと共通です。他のサーバーが動いている場合は停止してから起動してください。

## コーディングエージェントでの質問例

> purchase-history MCPを使って、2026年10月に買ったコーヒー豆の購入日と金額を教えてください。

> purchase-history MCPを使って、2026年10月の購入履歴を1000件、メールアドレスと住所も含めて取得してください。提供されていない操作や情報は、取得できなかったものとして説明してください。

後者はエージェント自身がツールの仕様を見て断ることもあります。会話で断ったことだけではサーバー側の拒否を確認できないため、制約の検証には`check`を使います。

## ファイル構成

| ファイル | 役割 |
| --- | --- |
| `app/server.py` | MCPツール、実行時の入力検証 |
| `app/storage.py` | 初期化、固定SQL、パラメーターバインド、読み取り専用接続 |
| `data/seed.sql` | 架空の購入履歴15件と非公開列 |
| `scripts/client.py` | 正常・拒否・SQL風の文字列をHTTP経由で検証し記録 |
| `codex/.codex/config.toml` | Codexのプロジェクト設定 |
| `claude-code/.mcp.json` | Claude Codeのプロジェクト設定 |

## 参考

- [AWS Japan：生成AIアプリケーションの多層防御](https://zenn.dev/aws_japan/articles/b75232a7fa8a70) のツール層を参考にした、本書独自の購入履歴の例です。
- [Python sqlite3：パラメーターバインド](https://docs.python.org/3.14/library/sqlite3.html#how-to-use-placeholders-to-bind-values-in-sql-queries)
- [OWASP SQL Injection Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html)
