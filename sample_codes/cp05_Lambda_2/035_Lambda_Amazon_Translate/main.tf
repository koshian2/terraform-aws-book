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

# ロールを作成
resource "aws_iam_role" "lambda_role" {
  name = "LambdaTranslateRole"
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

# Amazon Translateを動かすためのポリシー。リソースベースのポリシー制御ができないので、リソースは*でOK
  name        = "TranslatePolicy"
  role        = aws_iam_role.lambda_role.id
resource "aws_iam_role_policy" "translate_policy" {

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "translate:TranslateText",
        ],
        Effect = "Allow",
        Resource = [
          "*"
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

# Lambdaの作成
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = ".cache/lambda_function.zip"
}

# Lambdaの作成
resource "aws_lambda_function" "s3_lambda" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "translate_lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  memory_size      = 256
  timeout          = 30
}