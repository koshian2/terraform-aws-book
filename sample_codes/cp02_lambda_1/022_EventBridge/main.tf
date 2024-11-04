terraform {
  backend "local" {
    path = ".cache/terraform.tfstate"
  }
}

variable "aws_profile_name" {
  type    = string
  default = "develop"
}

provider "aws" {
  profile = var.aws_profile_name
}

data "aws_caller_identity" "current" {}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = ".cache/lambda_function.zip"
}

resource "aws_lambda_function" "hello_world" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "hello_lambda_terraform"
  role             = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LambdaBasicExecutionRole"
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda.output_base64sha256
}

# スケジュールイベントルールの作成 (5分ごと)
resource "aws_cloudwatch_event_rule" "every_five_minutes" {
  name                = "every_five_minutes_rule"
  schedule_expression = "rate(5 minutes)"
}

# Lambda にイベントルールをターゲットとして追加
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.every_five_minutes.name
  target_id = "lambda"
  arn       = aws_lambda_function.hello_world.arn
}

# Lambda に EventBridge からの呼び出しを許可
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_world.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_five_minutes.arn
}