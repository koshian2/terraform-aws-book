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

# S3バケット名を入力
variable "s3_bucket_name" {
  type = string # terraform.tfvarsで規定
}

# S3バケットの作成
resource "aws_s3_bucket" "example_bucket" {
  bucket        = var.s3_bucket_name
  force_destroy = true # 開発用
}

# ロールを作成（assume_role_policyをJSONで直接記述するのもOK）
resource "aws_iam_role" "lambda_role" {
  name = "LambdaS3Role"
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

# S3に書き込みできるポリシーの作成
resource "aws_iam_policy" "s3_write_policy" {
  name        = "LambdaS3WritePolicy"
  description = "Policy granting Lambda access to S3"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:PutObject",
        ],
        Effect = "Allow",
        Resource = [
          "${aws_s3_bucket.example_bucket.arn}/*"
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

# 先ほど作成したポリシーのアタッチ
resource "aws_iam_role_policy_attachment" "s3_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.s3_write_policy.arn
}

# LambdaのZipファイルの作成
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = ".cache/lambda_function.zip"
}

# Lambda関数のデプロイ
resource "aws_lambda_function" "s3_lambda" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "s3_write_lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  memory_size      = 256
  timeout          = 30

  environment {
    variables = {
      "S3_BUCKET_NAME" = aws_s3_bucket.example_bucket.id
    }
  }
}