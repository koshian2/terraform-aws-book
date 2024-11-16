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
  region  = "ap-northeast-1" # 必要に応じてリージョンを変更
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

# Step Functions用のIAMロールを作成
resource "aws_iam_role" "step_functions_role" {
  name = "step_functions_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "states.amazonaws.com"
      }
    }]
  })
}

# Step FunctionsロールにSNSのイベント通知権限を付与
resource "aws_iam_role_policy" "step_functions_policy" {
  name = "step_functions_policy"
  role = aws_iam_role.step_functions_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "sns:Publish"
        ],
        Effect   = "Allow",
        Resource = aws_sns_topic.email_topic.arn
      }
    ]
  })
}

# Step Functionsのステートマシンを定義
resource "aws_sfn_state_machine" "state_machine" {
  name     = "SNSWaitStateMachine"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = templatefile("${path.module}/state_machine_definition.json.tftpl", {
    sns_topic_arn = aws_sns_topic.email_topic.arn
  })
}
