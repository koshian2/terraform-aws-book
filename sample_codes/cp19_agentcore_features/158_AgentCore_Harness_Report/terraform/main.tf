terraform {
  required_version = ">= 1.11, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "= 6.66.0" }
  }
  backend "local" { path = "terraform.tfstate" }
}

variable "aws_profile" {
  type    = string
  default = "develop"
}
variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}
variable "model_id" {
  type    = string
  default = "jp.anthropic.claude-sonnet-4-6"
}
provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
  default_tags {
    tags = { Project = "agentcore-harness-report", ManagedBy = "Terraform" }
  }
}
data "aws_caller_identity" "current" {}
data "aws_bedrock_inference_profile" "model" { inference_profile_id = var.model_id }

# 同じセッションで追加依頼できるように会話履歴を保存する。
resource "aws_bedrockagentcore_memory" "conversation" {
  name                  = "expense_report_conversation"
  event_expiry_duration = 7
}

resource "aws_iam_role" "harness" {
  name = "expense_report_harness_execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Principal = { Service = "bedrock-agentcore.amazonaws.com" }, Action = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}
resource "aws_iam_role_policy" "harness" {
  role = aws_iam_role.harness.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"], Resource = concat([data.aws_bedrock_inference_profile.model.inference_profile_arn], [for m in data.aws_bedrock_inference_profile.model.models : m.model_arn]) },
      { Effect = "Allow", Action = ["ecr-public:GetAuthorizationToken", "sts:GetServiceBearerToken"], Resource = "*" },
      { Effect = "Allow", Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"], Resource = "*" },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:DescribeLogStreams", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*" },
      { Effect = "Allow", Action = ["logs:DescribeLogGroups"], Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*" },
      { Effect = "Allow", Action = ["cloudwatch:PutMetricData"], Resource = "*", Condition = { StringEquals = { "cloudwatch:namespace" = "bedrock-agentcore" } } },
      { Effect = "Allow", Action = ["bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT"], Resource = ["arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default", "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default/workload-identity/harness_expense_report-*"] },
      { Effect = "Allow", Action = ["bedrock-agentcore:CreateEvent", "bedrock-agentcore:DeleteEvent", "bedrock-agentcore:GetEvent", "bedrock-agentcore:ListEvents", "bedrock-agentcore:RetrieveMemoryRecords"], Resource = aws_bedrockagentcore_memory.conversation.arn }
    ]
  })
}

resource "aws_bedrockagentcore_harness" "report" {
  harness_name          = "expense_report"
  execution_role_arn    = aws_iam_role.harness.arn
  environment_variables = {}
  model {
    bedrock_model_config {
      model_id   = var.model_id
      max_tokens = 16384
    }
  }
  system_prompt { text = file("${path.module}/../system_prompt.txt") }
  allowed_tools   = ["shell", "file_operations"]
  max_iterations  = 25
  max_tokens      = 60000
  timeout_seconds = 600
  memory {
    agentcore_memory_configuration {
      arn            = aws_bedrockagentcore_memory.conversation.arn
      messages_count = 100
    }
  }
  environment {
    agentcore_runtime_environment {
      network_configuration { network_mode = "PUBLIC" }
      lifecycle_configuration = [{ idle_runtime_session_timeout = 900, max_lifetime = 3600 }]
    }
  }
  depends_on = [aws_iam_role_policy.harness]
}
output "client_config" {
  value = {
    aws_profile = var.aws_profile
    aws_region  = var.aws_region
    harness_id  = aws_bedrockagentcore_harness.report.harness_id
    harness_arn = aws_bedrockagentcore_harness.report.arn
    memory_id   = aws_bedrockagentcore_memory.conversation.id
    model_id    = var.model_id
  }
}
