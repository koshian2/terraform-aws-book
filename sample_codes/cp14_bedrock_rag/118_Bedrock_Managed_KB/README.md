# Bedrock Managed Knowledge Base

国土交通省「移住・二地域居住等促進専門委員会」第1〜3回（2023年）の議事要旨を検索し、取得した原文を根拠に回答するサンプルです。

## フォルダ構成

- `terraform/`: AWS設定、文書用S3、KB専用IAMロール、Managed KB、出力。
- `scripts/`: 同期・検索・回答生成。
- `documents/`: 取り込み対象の本文3件と型付きメタデータ3件。
- `results/`: 実行時に生成する同期・検索・回答の記録（Git対象外）。

出典と加工内容は [SOURCES.md](SOURCES.md) を参照してください。

## 準備・デプロイ

Python 3.14、uv、Terraform 1.12以上（2.0未満）、AWS CLIを使用します。AWS providerは6.66.0に固定しています。AWSプロファイルの既定値は `develop`、リージョンは `ap-northeast-1` です。リソース名の接頭辞は `managed-kb` です。

デプロイ・同期・検索・削除のコマンドは [commands.sh](commands.sh) にまとめています。このディレクトリで、必要なコマンドを順に実行してください。

本文とメタデータは同梱済みです。TerraformがS3に配置し、`sync`がKBへの取り込みを開始して最大900秒待機します。文書を更新した場合はapplyとsyncを再実行します。Pythonは `terraform/` の出力 `client_config` からプロファイル等を取得します。

ローカル実行者にはデプロイ・PassRole、KB検索・同期、回答モデル呼び出しの権限が必要です。KB専用ロールには文書用S3の一覧・読み取り権限を付与します。

TerraformはPATH上の実行ファイルを使用します。

## 検索・回答

Managed KB、マネージド埋め込み、SMART_PARSING、マネージドリランキングを使用します。`Retrieve`で取得した原文・出典を表示し、`Converse`で回答します。回答用モデルの既定値は `terraform/variables.tf` の `model_id` を参照してください。

`--meeting` は会議番号の検索フィルターです。回答の引用が原文に対応するか確認してください。この資料は2023年当時の議論であり、現在の制度の案内ではありません。

## 後片付け

同期・質問処理の終了後に、`commands.sh` の削除手順を実行します。

KB、データソース、専用IAMロール、文書用S3を削除します。文書用S3は `force_destroy = true` のため、追加したオブジェクトも削除対象です。ローカルの資料・結果は残ります。
