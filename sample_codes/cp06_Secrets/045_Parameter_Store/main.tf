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
  default = "/terraform_book/sample_secret"
}

provider "aws" {
  profile = var.aws_profile_name
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# パラメーターストアからシークレットでない値を取得
data "aws_ssm_parameter" "sample_non_secrets" {
  name = "/terraform_book/sample_non_secret"
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
          "ssm:GetParameter"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.secret_name}"
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
      NON_SECRET_VALUE       = data.aws_ssm_parameter.sample_non_secrets.value # シークレットでない値はそのまま環境変数に格納
      PARAMETER_STORE_SECRET = var.secret_name                                 # シークレットはパラメーターストアの名前だけ登録
    }
  }
}