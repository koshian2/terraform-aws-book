terraform {
  backend "local" {
    path = ".cache/terraform.tfstate"
  }
}

variable "aws_profile_name" {
  type    = string
  default = "develop"
}

variable "email_address" {
  type = string
}

provider "aws" {
  profile = var.aws_profile_name
}

# SNS トピックの作成
resource "aws_sns_topic" "email_topic" {
  name = "email-notification-topic"
}

# SNS トピックへのメール購読
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.email_topic.arn
  protocol  = "email"
  endpoint  = var.email_address
}

# FIFOキューの作成
resource "aws_sqs_queue" "fifo_queue" {
  name                        = "my-mail-queue.fifo" # FIFOキュー名は .fifo で終わる必要があり
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 43200
  receive_wait_time_seconds   = 10
  visibility_timeout_seconds  = 60
}

# Lambda用のロール
resource "aws_iam_role" "lambda_role" {
  name = "LambdaSQSEmailExecutionRole"

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

# IAM ロールポリシーの設定 (SQS 及び SNS のアクセス許可)
resource "aws_iam_role_policy" "sqs_policy" {
  name = "LambdaSQSSNSPolicy"
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
          aws_sqs_queue.fifo_queue.arn
        ]
      },
      {
        Action = [
          "sns:Publish"
        ],
        Effect = "Allow",
        Resource = [
          aws_sns_topic.email_topic.arn
        ]
      }
    ]
  })
}

# AWSLambdaBasicExecutionRoleマネージドポリシー
resource "aws_iam_role_policy_attachment" "managed_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# LambdaのZip
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = ".cache/lambda_function.zip"
}

# Lambdaの作成
resource "aws_lambda_function" "sqs_trigger_lambda" {
  filename                       = data.archive_file.lambda.output_path
  function_name                  = "sqs_email_lambda"
  role                           = aws_iam_role.lambda_role.arn
  handler                        = "lambda_function.lambda_handler"
  runtime                        = "python3.12"
  source_code_hash               = data.archive_file.lambda.output_base64sha256
  timeout                        = 10
  reserved_concurrent_executions = 1 # 同時実行数を1

  environment {
    variables = {
      "SNS_TOPIC_ARN" = aws_sns_topic.email_topic.arn
    }
  }
}

# Lambda のイベントソースマッピング (SQS から Lambda へのトリガー)
resource "aws_lambda_event_source_mapping" "sqs_fifo_event" {
  event_source_arn = aws_sqs_queue.fifo_queue.arn
  function_name    = aws_lambda_function.sqs_trigger_lambda.arn
  enabled          = true
  batch_size       = 1
}

# SQS キューの URL を出力
output "fifo_sqs_queue_url" {
  value = aws_sqs_queue.fifo_queue.id
}