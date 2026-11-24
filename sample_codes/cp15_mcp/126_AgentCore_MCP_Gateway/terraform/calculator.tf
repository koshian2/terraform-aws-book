resource "aws_iam_role" "calculator" {
  name_prefix = "${var.name}-calculator-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "calculator" {
  name              = "/aws/lambda/${var.name}_calculator"
  retention_in_days = 7
}

resource "aws_iam_role_policy" "calculator" {
  role = aws_iam_role.calculator.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.calculator.arn}:*"
    }]
  })
}

resource "aws_lambda_function" "calculator" {
  function_name    = "${var.name}_calculator"
  role             = aws_iam_role.calculator.arn
  filename         = "${path.module}/../build/calculator.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/calculator.zip")
  runtime          = "python3.14"
  architectures    = ["arm64"]
  handler          = "handler.handler"
  timeout          = 10
  memory_size      = 128
  depends_on       = [aws_iam_role_policy.calculator]
}

resource "aws_bedrockagentcore_gateway_target" "calculator" {
  name               = "calculator"
  gateway_identifier = aws_bedrockagentcore_gateway.hello.gateway_id
  credential_provider_configuration {
    gateway_iam_role {}
  }
  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.calculator.arn
        tool_schema {
          inline_payload {
            name        = "add"
            description = "Add two finite numbers and return their sum."
            input_schema {
              type = "object"
              property {
                name     = "a"
                type     = "number"
                required = true
              }
              property {
                name     = "b"
                type     = "number"
                required = true
              }
            }
          }
        }
      }
    }
  }
  depends_on = [aws_iam_role_policy.gateway]
}
