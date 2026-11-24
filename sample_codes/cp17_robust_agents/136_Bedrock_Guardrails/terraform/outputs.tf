output "client_config" {
  value = {
    aws_profile       = var.aws_profile
    aws_region        = "ap-northeast-1"
    function_name     = aws_lambda_function.guide.function_name
    guardrail_id      = aws_bedrock_guardrail.guide.guardrail_id
    guardrail_version = "DRAFT"
  }
}

output "lambda_inference_policy" {
  value = aws_iam_role_policy.inference.policy
}

# ローカル実行者用の権限例。既存のdevelopプロファイルの権限は変更しない。
output "local_client_policy" {
  value = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "bedrock:ApplyGuardrail", Resource = concat([aws_bedrock_guardrail.guide.guardrail_arn], local.guardrail_profiles) },
    { Effect = "Allow", Action = "lambda:InvokeFunction", Resource = aws_lambda_function.guide.arn }
  ] })
}
