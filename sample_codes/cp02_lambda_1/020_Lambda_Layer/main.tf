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

resource "aws_lambda_layer_version" "numpy_layer" {
  filename            = "./numpy.zip"
  layer_name          = "numpy_layer"
  description         = "A layer containing numpy library"
  compatible_runtimes = ["python3.12"]
  source_code_hash    = filebase64sha256("./numpy.zip")
}

resource "aws_lambda_function" "numpy_linear_algebra" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "numpy_linear_algebra"
  role             = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LambdaBasicExecutionRole"
  handler          = "lambda_function.lambda_handler"
  timeout          = 30
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda.output_base64sha256

  layers = [
    aws_lambda_layer_version.numpy_layer.arn # 追加したレイヤーを指定
  ]
}
