locals {
  interceptor_name = "${var.name}_request"
  interceptor_zip  = "${path.module}/../build/interceptor.zip"
}

resource "aws_iam_role" "interceptor" {
  name = "${var.name}_interceptor"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "interceptor" {
  name              = "/aws/lambda/${local.interceptor_name}"
  retention_in_days = 7
}

resource "aws_iam_role_policy" "interceptor" {
  role = aws_iam_role.interceptor.id
  name = "request_logs"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.interceptor.arn}:*"
      }
    ]
  })
}

resource "aws_lambda_function" "request" {
  function_name    = local.interceptor_name
  role             = aws_iam_role.interceptor.arn
  runtime          = "python3.14"
  handler          = "interceptor.handler"
  architectures    = ["arm64"]
  filename         = local.interceptor_zip
  source_code_hash = filebase64sha256(local.interceptor_zip)
  timeout          = 45
  memory_size      = 256
  depends_on       = [aws_iam_role_policy.interceptor, aws_cloudwatch_log_group.interceptor]
}

resource "aws_iam_role_policy" "invoke_interceptor" {
  role = aws_iam_role.gateway.id
  name = "invoke_request_interceptor"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow", Action = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.request.arn
    }]
  })
}

output "interceptor_function_name" {
  value = aws_lambda_function.request.function_name
}
