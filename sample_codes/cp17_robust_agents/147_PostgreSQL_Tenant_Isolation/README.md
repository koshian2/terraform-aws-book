# PostgreSQLのRLSとテナント別ビュー

ローカルPostgreSQLで、SQLにテナント条件を書き忘れても他社データが見えない構成を確認します。RLSを主な実装とし、テナント別ビューによる分離と比較します。AWSリソースやMCPサーバーは作成しません。

## 構成

Docker ComposeでPostgreSQL 18とPython 3.14の検証コンテナを起動します。DBポートはホストに公開せず、PythonからCompose内のネットワーク経由で接続します。ホスト側のPython・uvは不要です。

| 方式 | 接続ユーザー | 読み取り対象 | 制限する仕組み |
| --- | --- | --- | --- |
| RLS | 共通の`rls_app` | `rls_demo.inquiries` | DBセッションの所属と行の`tenant_id`をRLSで照合 |
| ビュー | `view_a`／`view_b` | `view_demo.tenant_a`／`tenant_b` | 固定条件のビューと、各ビューへのSELECT権限 |

比較を独立させるため、RLS用とビュー用に同じデータを持つ別テーブルを作ります。どちらもA社のT001は「商品が届きません。」、B社のT001は「請求書の宛名を変更してください。」です。

管理者は初期化だけに使い、検証は非管理者・非所有者・BYPASSRLSなしのDBユーザーで行います。ビューには`security_barrier`を設定し、元テーブルへの直接アクセスは許可しません。

## 実行環境

### Windows：WSLで実行

WSL 2のUbuntuなどを使います。Docker Desktopを使う場合はLinuxコンテナを有効にし、Settings → Resources → WSL Integrationで使用するディストリビューションとの連携を有効にしてください。WSL内のDocker Engine＋Composeプラグインでも実行できます。

**UbuntuなどのWSLターミナル**を開き、取得したサンプルの`compose.yaml`と`commands.sh`があるディレクトリへ移動します。Windows側に保存したファイルは、WSLから`/mnt/c/`などのドライブのマウント先を通じて参照できます。

### macOS：ターミナルで実行

Docker Desktopなど、Docker EngineとComposeが利用できる環境を起動し、ターミナルでこのサンプルのディレクトリへ移動します。Intel Mac・Apple Siliconとも、ホストのCPUに対応したコンテナイメージを使います。

### 共通の実行手順

サンプル直下で`bash commands.sh`を実行します。起動・ビルド・検証・片付けのコマンドはすべて[commands.sh](commands.sh)にまとめています。

初回はイメージの取得が必要です。既存のDBデータがあれば再利用して検証を繰り返せます。`sql/01-init.sql`は空のDBボリュームを初期化するときだけ実行されるため、SQLを変更した場合はcommands.sh末尾の片付けでボリュームを削除してから再実行してください。

## 確認する結果

| ケース | 期待する結果 |
| --- | --- |
| RLS：所属A・Bでテナント条件なしのSELECT | 各社のT001だけ取得 |
| RLS：他社のtenant_idを明示してSELECT | 0行（SQL自体は成功） |
| RLS：所属未設定・未知の所属 | 0行 |
| RLS：同じ接続をA→B→Aで利用 | そのトランザクションの所属だけ取得 |
| RLS：コミット・ロールバック後 | 所属が残らず0行 |
| RLS：RLS無効化・所有者への切り替え・書き込み | 権限不足（SQLSTATE 42501） |
| ビュー：自社ビューを条件なしでSELECT | 自社のT001だけ取得 |
| ビュー：他社ビュー・元テーブルをSELECT | 権限不足（SQLSTATE 42501） |
| ビュー：他社DBユーザーへSET ROLE | 権限不足（SQLSTATE 42501） |
| ビュー：セッションの所属を他社へ変更 | 自社ビューの取得範囲は変わらない |

検証は実際のPostgreSQLへの接続で行い、全項目一致なら`PASS: all expected results matched`を表示します。実際の行データと期待値は`results/verification-*.json`へ保存します。想定外の例外や不一致があれば非ゼロで終了します。RLSの0行と、ビューへのアクセス自体の権限エラーを区別してください。

## 所属情報の扱いと検証範囲

RLS用のPython処理は、認証済みの所属を受け取るアプリケーションを想定し、教材では固定の`tenant-a`・`tenant-b`を渡します。認証からの伝播は50章を参照します。

`set_config('app.tenant_id', ..., true)`を明示的なトランザクション内で実行し、終了時に値を元へ戻します。パラメーター化して値を渡し、接続を使い回しても前のリクエストの所属を残さないことを検証します。

**このRLS方式では、共通DBユーザーで任意のSQLを実行できる相手は所属変数も変更できます。** 認証済みの所属を正しく設定するアプリケーションは信頼対象です。LLMへ自由なSQL実行やDB認証情報を渡す構成ではなく、テナント条件の書き忘れに対してDB側の制限を追加する例です。51章の「Runtimeが正しいセッションタグを付ける」という前提に対応します。

ビュー方式はテナント別DBユーザーの認証とGRANTで境界を作ります。比較ではA・B両方の認証情報を検証スクリプトが持ちますが、実際の利用者へ他社の認証情報を渡してはいけません。固定パスワードはこのローカル教材専用です。

## ファイル

- `compose.yaml`：DB・検証コンテナ・DBボリューム。
- `sql/01-init.sql`：デモデータ、DBユーザー、RLS、ビュー、権限。
- `scripts/verify.py`：両方式の実アクセス検証とJSON保存。
- `Dockerfile`：Python 3.14の実行環境。
- `pyproject.toml`・`requirements.txt`：依存定義と固定済みのコンテナ用依存一覧。
- `commands.sh`：実行・停止・片付け。

## 参考

- [PostgreSQL：Row Security Policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
- [PostgreSQL：Rules and Privileges](https://www.postgresql.org/docs/current/rules-privileges.html)
- [AWS：PostgreSQLのRLSによるテナント分離](https://docs.aws.amazon.com/prescriptive-guidance/latest/saas-multitenant-managed-postgresql/rls.html)
