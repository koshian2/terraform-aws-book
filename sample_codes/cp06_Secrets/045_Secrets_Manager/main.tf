terraform {
  backend "local" {
    path = ".cache/terraform.tfstate"
  }
}

variable "aws_profile_name" {
  type    = string
  default = "develop"
}

variable "secret_name" {
  type    = string
  default = "terraform_book_sample_secret2"
}

provider "aws" {
  profile = var.aws_profile_name
}

# ランダムなパスワードを生成
resource "random_password" "dummy_password" {
  length  = 16
  special = true
}

# Secrets Manager にシークレットを作成
resource "aws_secretsmanager_secret" "sample_secret" {
  name                    = var.secret_name
  description             = "Terraformの本のサンプルシークレット"
  recovery_window_in_days = 0 # 0で即時消去、7-30で指定日数経過後に消去
}

# シークレットに値を設定
resource "aws_secretsmanager_secret_version" "sample_secret_version" {
  secret_id = aws_secretsmanager_secret.sample_secret.id
  secret_string = jsonencode({
    password = random_password.dummy_password.result
  })
}

# ロールを作成
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

# パラメーターストアにアクセスするポリシーを追加
resource "aws_iam_role_policy" "lambda_ssm_policy" {
  name = "LambdaSSMPolicy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Effect   = "Allow",
        Resource = aws_secretsmanager_secret.sample_secret.arn
      }
    ]
  })
}

# AWSLambdaBasicExecutionRoleマネージドポリシー
resource "aws_iam_role_policy_attachment" "managed_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# LambdaのZipの作成
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = ".cache/lambda_function.zip"
}

# Lambdaの作成
resource "aws_lambda_function" "lambda_function" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "sample_authorizer_lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      SECRET_NAME = aws_secretsmanager_secret.sample_secret.name
    }
  }
}

# 出力 (オプション)
output "secret_arn" {
  description = "作成されたシークレットのARN"
  value       = aws_secretsmanager_secret.sample_secret.arn
}

