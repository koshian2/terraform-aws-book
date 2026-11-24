# AgentCore Memoryのテナント分離

共有のAgentCore MemoryとIAMロールを使い、STSセッションタグによってテナントごとのアクセス範囲を制限するサンプルです。短期記憶の会話イベントと、Semantic戦略で抽出する長期記憶の両方を確認します。

## 構成

```text
ローカルPython（信頼する管理者）
  ├─ AssumeRole：TenantId=tenant-a → A社の一時認証情報
  └─ AssumeRole：TenantId=tenant-b → B社の一時認証情報
                   ↓ IAMで認可
             共有AgentCore Memory
               ├─ 短期記憶：actorId
               └─ 長期記憶：namespace
```

| 対象 | 識別子の例 | IAMの条件 |
| --- | --- | --- |
| 短期記憶 | `tenant-a_alice_<実行ID>` | `bedrock-agentcore:actorId`が`${aws:PrincipalTag/TenantId}_*`に一致 |
| 長期記憶 | `/facts/tenant-a_alice_<実行ID>/` | `bedrock-agentcore:namespace`が`/facts/${aws:PrincipalTag/TenantId}_*/`に一致 |

テナントごとに旅行先と予算が異なる架空の会話を保存します。両テナントで同じsessionIdを使っても、actorIdで会話が区別されます。長期記憶の名前空間はactorId単位で、セッションをまたいで利用できます。

## 実行方法

Python 3.14、uv、Terraform 1.11以上2.0未満、AWS CLIを用意します。AWSプロファイルとリージョンの既定値は`terraform/main.tf`の`develop`と`ap-northeast-1`です。

実行・再取得・削除のコマンドは`commands.sh`にまとめています。WindowsはGit Bash、macOSはターミナルのbashで実行します。各ツールがそのシェルのPATHから利用できることを確認してください。

実行者にはMemory・戦略・IAMロールとポリシーの作成、および作成したロールへのAssumeRoleとTagSessionの権限が必要です。Terraformでは実行者のIAMロールを信頼先に設定するため、SSOなどのIAMロールセッションを使います。

## 確認する結果

| ケース | 期待する結果 |
| --- | --- |
| 自社actorIdへの会話保存・取得 | 保存した本文を取得できる |
| 他社actorIdへの会話保存・取得 | AccessDenied |
| 自社の長期記憶の一覧・検索 | 抽出された記憶を取得できる |
| 他社の長期記憶の一覧・検索 | AccessDenied |
| ルート名前空間・namespacePath・類似テナント名による参照 | AccessDenied |
| 記憶IDを直接指定するGetMemoryRecord | 操作を許可していないためAccessDenied |
| タグなし・未知のテナント・余分なタグでのAssumeRole | AccessDenied |
| テナント用の一時認証情報から別テナントへ再AssumeRole | AccessDenied |

クライアントは25項目を確認し、全項目を通過すると結果の`status`が`passed`になります。拒否ケースは実際のAWS APIのAccessDeniedを確認し、空の検索結果を拒否成功とは扱いません。長期記憶は両社のデータが生成されたことを確認してから越境参照を試します。

結果と取得した会話・記憶は`results/latest.json`へ保存します。長期記憶の抽出は非同期です。600秒以内に揃わなければ`incomplete_observation`と終了コード2になり、長期記憶の検証は未完了です。後から`show`で生成状況を確認できます。`demo`を再実行すると別のactorIdとsessionIdを作成します。

## 分離の範囲

このサンプルが保証する境界はテナント間です。同じテナントに属する別ユーザーのactorIdも、そのテナントの認証情報からはアクセスできます。ユーザー単位の分離が必要なら、条件と識別子の設計を追加します。

ローカルPythonは信頼する管理者として両社の認証情報を取得します。実際のアプリでは、認証済みの所属情報から信頼するバックエンドがTenantIdを決定し、利用者やLLMにタグを選ばせないことが前提です。Cognitoによる認証と所属情報の伝播は、このサンプルの検証範囲には含みません。

GetMemoryRecordなど名前空間の条件を使わない操作は許可していません。Memoryへの広いアクセス権を別途付与すると境界が変わるため、本サンプルでは示した操作に権限を限定します。

## ファイル

| パス | 内容 |
| --- | --- |
| `terraform/` | Memory・Semantic戦略・共有IAMロールとポリシー |
| `scripts/client.py` | 保存・取得と正常／越境アクセスの確認 |
| `data/conversations.json` | 架空の会話データ |
| `commands.sh` | 実行と片付けの手順 |

## 参考資料

- [AgentCore Memoryの構成とアクセス制御](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/memory-organization.html)
- [IAMセッションタグ](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_session-tags.html)
