terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

variable "aws_profile" {
  description = "Terraformを実行するAWS CLIプロファイル名"
  type        = string
  default     = "develop"
}

provider "aws" {
  profile = var.aws_profile
  region  = "ap-northeast-1"
}

locals {
  function_name     = "aip-company-a-demo"
  system_defined_id = "jp.anthropic.claude-sonnet-4-6"
}

# 参照元プロファイルと、推論先の各リージョンのモデルARNを取得する。
data "aws_bedrock_inference_profile" "sonnet" {
  inference_profile_id = local.system_defined_id
}

resource "aws_bedrock_inference_profile" "company_a" {
  name        = "a-company-sonnet"
  description = "Claude Sonnet 4.6 inference for Company A"

  model_source {
    copy_from = data.aws_bedrock_inference_profile.sonnet.inference_profile_arn
  }

  # Cost Explorerで集計するには、BillingでProjectタグを別途有効化する。
  tags = {
    Project = "CompanyA"
  }
}

resource "aws_iam_role" "lambda" {
  name = "${local.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# この実行ロールに、別途広いBedrock推論権限を付与しないこと。
# 条件付きAllowは、他のポリシーによるAllowを打ち消さない。
resource "aws_iam_role_policy" "inference" {
  name = "inference-via-company-a-only"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowSpecificAIP"
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
      ]
      Resource = aws_bedrock_inference_profile.company_a.arn
      }, {
      Sid    = "AllowModelsViaSpecificAIPOnly"
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
      ]
      Resource = [for model in data.aws_bedrock_inference_profile.sonnet.models : model.model_arn]
      Condition = {
        ArnEquals = {
          "bedrock:InferenceProfileArn" = aws_bedrock_inference_profile.company_a.arn
        }
      }
    }]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 7
}

resource "aws_iam_role_policy" "logs" {
  name = "write-function-logs"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
    }]
  })
}

# ZIPはTerraform内で生成する。boto3はLambdaのPythonランタイム同梱版を使用。
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/cache/lambda_function.zip"
}

resource "aws_lambda_function" "demo" {
  function_name    = local.function_name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.14"
  handler          = "lambda_function.lambda_handler"
  timeout          = 120
  memory_size      = 256
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      AIP_ARN           = aws_bedrock_inference_profile.company_a.arn
      SYSTEM_DEFINED_ID = local.system_defined_id
    }
  }

  depends_on = [aws_iam_role_policy.inference, aws_iam_role_policy.logs]
}

output "function_name" {
  value = aws_lambda_function.demo.function_name
}

output "aip_arn" {
  value = aws_bedrock_inference_profile.company_a.arn
}

output "inference_policy_json" {
  description = "作成したAIPと参照先モデルのARNを含む、本文に対応するIAMポリシー"
  value       = aws_iam_role_policy.inference.policy
}
