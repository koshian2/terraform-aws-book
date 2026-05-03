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

# 標準キューの作成 / Create standard queue
resource "aws_sqs_queue" "standard_queue" {
  name                       = "my-standard-queue"
  message_retention_seconds  = 43200 # 12時間 / 12 hours
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 30

  # 再試行ポリシー / Retry policy
  redrive_policy = jsonencode({
    maxReceiveCount     = 5
    deadLetterTargetArn = aws_sqs_queue.standard_dlq.arn
  })
}

# デッドレターキューの作成 (標準キュー用) / Create dead letter queue (for standard queue)
resource "aws_sqs_queue" "standard_dlq" {
  name                       = "my-standard-dlq"
  message_retention_seconds  = 604800 # 7日間 / 7 days
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 30
}

# Lambda用のロール / Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "LambdaSQSExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# SQSからキューを読み書きできるインラインポリシー / Inline policy for reading/writing SQS queues
resource "aws_iam_role_policy" "sqs_policy" {
  name = "LambdaSQSPolicy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ],
        Effect = "Allow",
        Resource = [
          aws_sqs_queue.standard_queue.arn,
          aws_sqs_queue.standard_dlq.arn
        ]
      }
    ]
  })
}

# AWSLambdaBasicExecutionRoleマネージドポリシー / AWSLambdaBasicExecutionRole managed policy
resource "aws_iam_role_policy_attachment" "managed_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# LambdaのZip / Lambda Zip
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = ".cache/lambda_function.zip"
}

# Lambdaの作成 / Create Lambda
resource "aws_lambda_function" "sqs_standard_trigger_lambda" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "sqs_standard_redrive_lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 5
}


# Lambdaのイベントソースマッピング / Lambda event source mapping
resource "aws_lambda_event_source_mapping" "sqs_standard_event" {
  event_source_arn = aws_sqs_queue.standard_queue.arn
  function_name    = aws_lambda_function.sqs_standard_trigger_lambda.arn
  enabled          = true
  batch_size       = 1
}

# SQSのURLを出力 (標準キュー) / Output SQS URL (standard queue)
output "standard_sqs_queue_url" {
  value = aws_sqs_queue.standard_queue.id
}

# デッドレターキューのURLを出力 (標準キュー用) / Output dead letter queue URL (for standard queue)
output "standard_sqs_dlq_url" {
  value = aws_sqs_queue.standard_dlq.id
}