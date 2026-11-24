# このディレクトリで、必要なコマンドを順に実行する。
# 前提: TerraformとAWS CLIを導入し、developでSonnet 4.6を利用可能にする。
# 未ログイン、またはセッションの有効期限が切れている場合に実行する。
# aws sso login --profile develop

# AIP・実行ロール・Lambdaを作成する。ZIPはTerraformが生成する。
terraform init
terraform plan
terraform apply

# AIP経由: payloads/response_aip.jsonにstatusCode 200と回答が返ることを確認する。
aws lambda invoke --profile develop --region ap-northeast-1 \
  --function-name aip-company-a-demo \
  --cli-binary-format raw-in-base64-out \
  --payload file://payloads/event_aip.json payloads/response_aip.json
cat payloads/response_aip.json

# system-defined経由: FunctionErrorと、応答内のAccessDeniedExceptionを確認する。
# CLI自体の終了コードやStatusCode 200は、関数内の推論成功を意味しない。
aws lambda invoke --profile develop --region ap-northeast-1 \
  --function-name aip-company-a-demo \
  --cli-binary-format raw-in-base64-out \
  --payload file://payloads/event_system_defined.json payloads/response_system_defined.json
cat payloads/response_system_defined.json

# コスト集計には、BillingコンソールでProjectコスト配分タグの有効化が必要。
# 検証後の削除は、次のコマンドを別途実行する。
# terraform destroy
