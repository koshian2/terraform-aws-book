terraform {
  backend "local" {
    path = ".cache/terraform.tfstate"
  }
}

variable "aws_profile_name" {
  type    = string
  default = "develop"
}

variable "environments_list" {
  type    = list(string)
  default = ["dev", "stg", "prod"]
}

variable "environments_map" {
  type = map(string)
  default = {
    "dev"  = "development"
    "stg"  = "staging"
    "prod" = "production"
  }
}

variable "environments_with_setting" {
  type = map(object({
    env_name = string
    memory   = number
  }))
  default = {
    "dev"  = { "env_name" = "development", "memory" = 128 },
    "stg"  = { "env_name" = "staging", "memory" = 256 },
    "prod" = { "env_name" = "production", "memory" = 512 }
  }
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

# listの場合はtoset()でsetに変換
resource "aws_lambda_function" "env_sample1" {
  for_each         = toset(var.environments_list)
  filename         = data.archive_file.lambda.output_path
  function_name    = "env_sample1_${each.value}"
  role             = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LambdaBasicExecutionRole"
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      ENV_NAME = each.value # each.keyでも同じ
    }
  }
}

# mapはそのまま突っ込むでOK
resource "aws_lambda_function" "env_sample2" {
  for_each         = var.environments_map
  filename         = data.archive_file.lambda.output_path
  function_name    = "env_sample2_${each.key}"
  role             = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LambdaBasicExecutionRole"
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      ENV_NAME = each.value # development, staging, productionの略していない値が格納される
    }
  }
}

# 複雑にネストした型
resource "aws_lambda_function" "env_sample3" {
  for_each         = var.environments_with_setting
  filename         = data.archive_file.lambda.output_path
  function_name    = "env_sample3_${each.key}"
  role             = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LambdaBasicExecutionRole"
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  memory_size      = each.value.memory
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      ENV_NAME = each.value.env_name
    }
  }
}