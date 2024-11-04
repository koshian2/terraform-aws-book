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

resource "aws_lambda_function" "prime_number" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "count_primes"
  role             = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LambdaBasicExecutionRole"
  handler          = "lambda_function.lambda_handler"
  timeout          = 30
  memory_size      = 128
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda.output_base64sha256
}