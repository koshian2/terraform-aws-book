# AgentCore Memory：4種類の長期記憶を比較する

同じ旅行の会話をAgentCore Memoryに保存し、Semantic・User preference・Summary・Episodicの4つの戦略が抽出した記憶を比較します。返された本文を加工せずそのまま表示するため、元の会話と抽出結果を照合できます。

## 構成と準備

| ファイル | 役割 |
|---|---|
| `scripts/client.py` | 会話の投入、抽出結果の観測・再取得 |
| `data/conversation.json` | 京都旅行についての架空の9発言 |
| `terraform/main.tf` | Memoryと接続先の設定 |
| `terraform/strategies.tf` | 4戦略と保存先namespaceの設定 |
| `commands.sh` | 準備から後片付けまでの実行コマンド |

Python 3.14、uv、Terraform 1.11以上、AWS CLIを使用します。AWSプロファイルは`develop`、リージョンは`ap-northeast-1`です。設定は`terraform/main.tf`の変数で変更します。

利用するAWS認証情報にはMemory・戦略の作成・更新・参照・削除・タグ管理、`bedrock-agentcore:CreateEvent`・`ListEvents`・`ListMemoryRecords`の権限が必要です。抽出にはAWSの組み込み戦略を使います。このサンプルの出力は抽出された記憶であり、それを使った質問への回答生成は含みません。

## 比較する4戦略

| 戦略 | 確認する内容 | namespace |
|---|---|---|
| Semantic | 旅行先・予算・決定事項などの事実 | `/facts/{actorId}/` |
| User preference | 静かな庭園が好き、混雑を避けたいなどの好み・選択 | `/preferences/{actorId}/` |
| Summary | 旅行の振り返りの要点 | `/summaries/{actorId}/{sessionId}/` |
| Episodic | 混雑での失敗、代替先への変更、結果と学び | `/episodes/{actorId}/{sessionId}/` |

SemanticとUser preferenceはactor単位、SummaryとEpisodicのエピソードはactorとsessionの組み合わせで保存先を分けています。この例では1回の会話からの抽出を比較します。

Episodicにはエピソードと、それらを横断するReflectionがあります。Reflectionの保存先は同じactor内の親namespace（`/episodes/{actorId}/`）に設定しています。今回の一覧・完了判定ではセッション内のエピソードを対象とし、複数エピソードからのReflection生成までは検証しません。

## 実行と確認

実行コマンドは[commands.sh](commands.sh)にまとめています。このサンプル直下でセクションごとに実行してください。WindowsではPowerShellに各コマンドを貼り付け、macOSではシェルから実行できます。

1. TerraformでMemoryと4戦略を作成します。同じMemoryに対する戦略の変更は順番に行われます。
2. `demo`で会話を保存し、20秒間隔で最大600秒、抽出結果を観測します。毎回新しいactor IDを発行します。
3. 標準出力と`results/latest.json`で、入力の`submitted_conversation`と各戦略の`records`内の本文を比較します。
4. 再確認は表示されたactor IDを指定して`show`を使います。`show`は会話を再投入せず、AWSから結果を取得します。

4戦略すべてに1件以上の記憶が見つかると`records_observed`で終了します。時間内に揃わない場合は`incomplete_observation`と終了コード2を返します。これは抽出の失敗と断定するものではありません。同じactor IDで後から再取得してください。待機時間は`--wait-seconds`で0～900秒に変更できます。

## 結果の読み方

入力は旅行後の振り返りです。人気の庭園で40分待ったため、混雑状況を確認して近隣の庭園に変更し、予算内で静かに過ごせたという経験を含みます。Semanticは旅行先・費用など、User preferenceは静かな庭園への好み、Summaryは会話全体の要点、Episodicは状況・行動・結果・学びがどう残ったかを比較します。

Episodicはエピソードの完了を検出してから記録を生成します。入力には旅行と振り返りの完了を明記していますが、抽出時間や生成結果は保証されません。他の3戦略だけが先に揃う場合も、同じactor IDで再取得してください。

戦略間で内容が重複する場合があり、出力の件数・形式・文言も固定ではありません。「今回は街歩きをしない」という選択を恒久的な好みに読み替えないよう、抽出本文の文脈も読みます。各戦略でレコードが確認できたとしても、全情報の抽出完了や内容の正確さを保証するものではありません。時間を置いた再取得で追加の記憶が見つかる場合もあります。

## 後片付け

短期イベントの保持期間は7日です。長期記憶を同じ期限で消す設定ではありません。終了後は`commands.sh`末尾の削除計画を確認して適用します。Memoryと4戦略、保存した会話と抽出された記憶が削除されます。ローカルの`results/`には観測結果が残ります。

## 参考

- [AWS：Episodic memory strategy](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/episodic-memory-strategy.html)
