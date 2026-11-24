resource "aws_iam_role" "pre_token" {
  name_prefix = "${var.name}-token-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "pre_token" {
  name              = "/aws/lambda/${var.name}_pre_token"
  retention_in_days = 7
}

resource "aws_iam_role_policy" "pre_token" {
  role = aws_iam_role.pre_token.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.pre_token.arn}:*"
    }]
  })
}

resource "aws_lambda_function" "pre_token" {
  function_name    = "${var.name}_pre_token"
  role             = aws_iam_role.pre_token.arn
  runtime          = "python3.14"
  handler          = "pre_token.handler"
  architectures    = ["arm64"]
  filename         = "${path.module}/../build/pre_token.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/pre_token.zip")
  timeout          = 10
  environment { variables = { TENANT_TIERS = jsonencode(local.tenant_tiers) } }
  depends_on = [aws_iam_role_policy.pre_token]
}

resource "aws_lambda_permission" "pre_token" {
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.pre_token.function_name
  principal      = "cognito-idp.amazonaws.com"
  source_arn     = aws_cognito_user_pool.users.arn
  source_account = data.aws_caller_identity.current.account_id
}
