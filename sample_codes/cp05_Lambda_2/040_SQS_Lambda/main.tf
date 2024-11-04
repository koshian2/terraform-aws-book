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

# 標準キューの作成
resource "aws_sqs_queue" "standard_queue" {
  name                       = "my-standard-queue"
  message_retention_seconds  = 43200
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 30
}

# FIFOキューの作成
resource "aws_sqs_queue" "fifo_queue" {
  name                        = "my-fifo-queue.fifo" # FIFOキュー名は .fifo で終わる必要があり
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 43200
  receive_wait_time_seconds   = 10
  visibility_timeout_seconds  = 30
}

# Lambda用のロール
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

# SQSからキューを読み書きできるインラインポリシー
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
          aws_sqs_queue.fifo_queue.arn
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
resource "aws_lambda_function" "sqs_standard_trigger_lambda" {
  filename                       = data.archive_file.lambda.output_path
  function_name                  = "sqs_standard_trigger_lambda"
  role                           = aws_iam_role.lambda_role.arn
  handler                        = "lambda_function.lambda_handler"
  runtime                        = "python3.12"
  source_code_hash               = data.archive_file.lambda.output_base64sha256
  reserved_concurrent_executions = 1 # 実験用に同時実行数を1に絞っておくとわかりやすい
  timeout                        = 5
}

resource "aws_lambda_function" "sqs_fifo_trigger_lambda" {
  filename                       = data.archive_file.lambda.output_path
  function_name                  = "sqs_fifo_trigger_lambda"
  role                           = aws_iam_role.lambda_role.arn
  handler                        = "lambda_function.lambda_handler"
  runtime                        = "python3.12"
  source_code_hash               = data.archive_file.lambda.output_base64sha256
  reserved_concurrent_executions = 1 # 実験用に同時実行数を1に絞っておくとわかりやすい
  timeout                        = 5
}


# Lambdaのイベントソースマッピング
resource "aws_lambda_event_source_mapping" "sqs_standard_event" {
  event_source_arn = aws_sqs_queue.standard_queue.arn
  function_name    = aws_lambda_function.sqs_standard_trigger_lambda.arn
  enabled          = true
  batch_size       = 1
}

resource "aws_lambda_event_source_mapping" "sqs_fifo_event" {
  event_source_arn = aws_sqs_queue.fifo_queue.arn
  function_name    = aws_lambda_function.sqs_fifo_trigger_lambda.arn
  enabled          = true
  batch_size       = 1
}

# SQSのURLを出力
output "standard_sqs_queue_url" {
  value = aws_sqs_queue.standard_queue.id
}

output "fifo_sqs_queue_url" {
  value = aws_sqs_queue.fifo_queue.id
}