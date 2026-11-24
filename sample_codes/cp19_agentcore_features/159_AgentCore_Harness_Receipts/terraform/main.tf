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
    tags = { Project = "agentcore-harness-receipts", ManagedBy = "Terraform" }
  }
}
data "aws_caller_identity" "current" {}
data "aws_bedrock_inference_profile" "model" { inference_profile_id = var.model_id }

resource "aws_s3_bucket" "skills" {
  bucket_prefix = "receipt-skills-"
  force_destroy = true
}
resource "aws_s3_bucket_public_access_block" "skills" {
  bucket                  = aws_s3_bucket.skills.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_object" "skill" {
  for_each     = fileset("${path.module}/../skills", "**/*.md")
  bucket       = aws_s3_bucket.skills.id
  key          = "skills/${each.value}"
  source       = "${path.module}/../skills/${each.value}"
  source_hash  = filemd5("${path.module}/../skills/${each.value}")
  content_type = "text/markdown; charset=utf-8"
}

# 利用者の確認回答を同じ会話へ引き継ぐ。
resource "aws_bedrockagentcore_memory" "conversation" {
  name                  = "receipt_skills_conversation"
  event_expiry_duration = 7
}

resource "aws_iam_role" "harness" {
  name = "receipt_skills_harness_execution"
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
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.skills.arn}/skills/expense-processing/*" },
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.skills.arn, Condition = { StringLike = { "s3:prefix" = ["skills/expense-processing", "skills/expense-processing/*"] } } },
      { Effect = "Allow", Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"], Resource = concat([data.aws_bedrock_inference_profile.model.inference_profile_arn], [for m in data.aws_bedrock_inference_profile.model.models : m.model_arn]) },
      { Effect = "Allow", Action = ["ecr-public:GetAuthorizationToken", "sts:GetServiceBearerToken"], Resource = "*" },
      { Effect = "Allow", Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"], Resource = "*" },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:DescribeLogStreams", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*" },
      { Effect = "Allow", Action = ["logs:DescribeLogGroups"], Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*" },
      { Effect = "Allow", Action = ["cloudwatch:PutMetricData"], Resource = "*", Condition = { StringEquals = { "cloudwatch:namespace" = "bedrock-agentcore" } } },
      { Effect = "Allow", Action = ["bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT"], Resource = ["arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default", "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default/workload-identity/harness_receipt_skills-*"] },
      { Effect = "Allow", Action = ["bedrock-agentcore:CreateEvent", "bedrock-agentcore:DeleteEvent", "bedrock-agentcore:GetEvent", "bedrock-agentcore:ListEvents", "bedrock-agentcore:RetrieveMemoryRecords"], Resource = aws_bedrockagentcore_memory.conversation.arn }
    ]
  })
}

resource "aws_bedrockagentcore_harness" "report" {
  harness_name          = "receipt_skills"
  execution_role_arn    = aws_iam_role.harness.arn
  environment_variables = { RECEIPT_MODEL_ID = var.model_id, RECEIPT_AWS_REGION = var.aws_region }
  model {
    bedrock_model_config {
      model_id   = var.model_id
      max_tokens = 16384
    }
  }
  system_prompt { text = file("${path.module}/../system_prompt.txt") }
  skill {
    s3 { uri = "s3://${aws_s3_bucket.skills.id}/skills/expense-processing/" }
  }
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
  depends_on = [aws_iam_role_policy.harness, aws_s3_object.skill, aws_s3_bucket_public_access_block.skills]
}
output "client_config" {
  value = {
    aws_profile  = var.aws_profile
    aws_region   = var.aws_region
    harness_id   = aws_bedrockagentcore_harness.report.harness_id
    harness_arn  = aws_bedrockagentcore_harness.report.arn
    memory_id    = aws_bedrockagentcore_memory.conversation.id
    model_id     = var.model_id
    skill_bucket = aws_s3_bucket.skills.id
  }
}
