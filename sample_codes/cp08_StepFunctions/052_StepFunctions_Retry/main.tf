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
  region  = "ap-northeast-1" # 必要に応じてリージョンを変更 / Change region as needed
}

# Lambda用のIAMロールを作成 / Create IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "LambdaExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# AWSLambdaBasicExecutionRoleポリシーをアタッチ / Attach AWSLambdaBasicExecutionRole policy
resource "aws_iam_role_policy_attachment" "managed_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 定義するLambda関数のリスト / List of Lambda functions to define
locals {
  lambda_functions = [
    "lambda_process",
    "lambda_success"
  ]
}

# Lambda関数のZIPファイルを作成 / Create ZIP files for Lambda functions
data "archive_file" "lambdas" {
  for_each    = toset(local.lambda_functions)
  type        = "zip"
  source_file = "${each.value}.py"
  output_path = ".cache/${each.value}.zip"
}

# Lambda関数を作成 / Create Lambda functions
resource "aws_lambda_function" "lambda_functions" {
  for_each         = toset(local.lambda_functions)
  filename         = data.archive_file.lambdas[each.value].output_path
  function_name    = "stepfunction_${each.value}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "${each.value}.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambdas[each.value].output_base64sha256
}

# Step Functions用のIAMロールを作成 / Create IAM role for Step Functions
resource "aws_iam_role" "step_functions_role" {
  name = "step_functions_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "states.amazonaws.com"
      }
    }]
  })
}

# デッドレターキューの作成 / Create dead letter queue
resource "aws_sqs_queue" "dead_letter_queue" {
  name                       = "stepfunction_process_dlq"
  message_retention_seconds  = 86400 # 12h / 12 hours (note: 86400 sec is actually 24h)
  receive_wait_time_seconds  = 0
  visibility_timeout_seconds = 30
}

# Step FunctionsロールにLambda呼び出し権限を付与 / Grant Lambda invocation permission to Step Functions role
resource "aws_iam_role_policy" "step_functions_policy" {
  name = "step_functions_policy"
  role = aws_iam_role.step_functions_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "lambda:InvokeFunction"
        ],
        Effect   = "Allow",
        Resource = [for v in aws_lambda_function.lambda_functions : v.arn]
      },
      {
        Action = [
          "sqs:SendMessage"
        ],
        Effect   = "Allow",
        Resource = [aws_sqs_queue.dead_letter_queue.arn]
      }
    ]
  })
}

# Step Functionsのステートマシンを定義 / Define Step Functions state machine
resource "aws_sfn_state_machine" "state_machine" {
  name     = "RetryStateMachine"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = templatefile("${path.module}/state_machine_definition.json.tftpl", {
    processing_lambda_arn = aws_lambda_function.lambda_functions["lambda_process"].arn
    success_lambda_arn    = aws_lambda_function.lambda_functions["lambda_success"].arn
    dlq_queue_url         = aws_sqs_queue.dead_letter_queue.url
  })
}
