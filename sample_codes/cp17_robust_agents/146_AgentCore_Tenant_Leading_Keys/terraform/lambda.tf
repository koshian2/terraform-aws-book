resource "aws_iam_role" "lambda" {
  for_each    = toset(["pre_token", "context"])
  name_prefix = "${var.name}_${each.key}-"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.amazonaws.com" }
  }] })
}
resource "aws_cloudwatch_log_group" "lambda" {
  for_each          = aws_iam_role.lambda
  name              = "/aws/lambda/${var.name}_${each.key}"
  retention_in_days = 7
}
resource "aws_iam_role_policy" "lambda_logs" {
  for_each = aws_iam_role.lambda
  role     = each.value.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.lambda[each.key].arn}:*"
  }] })
}
resource "aws_lambda_function" "pre_token" {
  function_name    = "${var.name}_pre_token"
  role             = aws_iam_role.lambda["pre_token"].arn
  runtime          = "python3.14"
  handler          = "pre_token.handler"
  architectures    = ["arm64"]
  filename         = "${path.module}/../build/pre_token.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/pre_token.zip")
  timeout          = 10
  environment { variables = { ALLOWED_TENANTS = jsonencode(keys(local.tenants)) } }
  depends_on = [aws_iam_role_policy.lambda_logs]
}
resource "aws_lambda_permission" "pre_token" {
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.pre_token.function_name
  principal      = "cognito-idp.amazonaws.com"
  source_arn     = aws_cognito_user_pool.users.arn
  source_account = data.aws_caller_identity.current.account_id
}
resource "aws_lambda_function" "context" {
  function_name    = "${var.name}_context"
  role             = aws_iam_role.lambda["context"].arn
  runtime          = "python3.14"
  handler          = "interceptor.handler"
  architectures    = ["arm64"]
  filename         = "${path.module}/../build/interceptor.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/interceptor.zip")
  timeout          = 10
  environment { variables = {
    ALLOWED_TENANTS   = jsonencode(keys(local.tenants))
    COGNITO_ISSUER    = local.issuer
    COGNITO_CLIENT_ID = aws_cognito_user_pool_client.local.id
    INVOKE_SCOPE      = local.invoke_scope
  } }
  depends_on = [aws_iam_role_policy.lambda_logs]
}
resource "aws_iam_role_policy" "invoke_interceptor" {
  role = aws_iam_role.gateway.id
  name = "inject_verified_tenant"
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = aws_lambda_function.context.arn
  }] })
}
