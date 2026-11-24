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

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
  default_tags {
    tags = { Project = "agentcore-memory-tenant-abac", ManagedBy = "Terraform" }
  }
}

data "aws_caller_identity" "current" {}
data "aws_iam_session_context" "deployer" {
  arn = data.aws_caller_identity.current.arn
}

resource "aws_bedrockagentcore_memory" "demo" {
  name                  = "tenant_abac_memory_demo"
  description           = "Shared Memory and shared role with tenant session tags"
  event_expiry_duration = 7
}

resource "aws_bedrockagentcore_memory_strategy" "semantic" {
  name                = "tenant_facts"
  memory_id           = aws_bedrockagentcore_memory.demo.id
  type                = "SEMANTIC"
  namespace_templates = ["/facts/{actorId}/"]
}

# The trusted demo administrator simulates two tenants. End users must not
# receive this ability to choose their own TenantId.
resource "aws_iam_role" "tenant" {
  name_prefix = "memory-tenant-abac-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = data.aws_iam_session_context.deployer.issuer_arn }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals                = { "aws:RequestTag/TenantId" = ["tenant-a", "tenant-b"] }
        "ForAllValues:StringEquals" = { "aws:TagKeys" = ["TenantId"] }
        Null                        = { "aws:RequestTag/TenantId" = "false" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "memory" {
  role = aws_iam_role.tenant.id
  name = "tenant-memory-access"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "OwnShortTermEvents"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:CreateEvent", "bedrock-agentcore:ListEvents"]
        Resource = aws_bedrockagentcore_memory.demo.arn
        Condition = {
          StringLike = { "bedrock-agentcore:actorId" = "$${aws:PrincipalTag/TenantId}_*" }
          Null       = { "aws:PrincipalTag/TenantId" = "false" }
        }
      },
      {
        Sid      = "OwnLongTermNamespace"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:ListMemoryRecords", "bedrock-agentcore:RetrieveMemoryRecords"]
        Resource = aws_bedrockagentcore_memory.demo.arn
        Condition = {
          StringLike = { "bedrock-agentcore:namespace" = "/facts/$${aws:PrincipalTag/TenantId}_*/" }
          Null       = { "aws:PrincipalTag/TenantId" = "false" }
        }
      }
    ]
  })
}

output "client_config" {
  value = {
    aws_profile = var.aws_profile
    aws_region  = var.aws_region
    memory_id   = aws_bedrockagentcore_memory.demo.id
    strategy_id = aws_bedrockagentcore_memory_strategy.semantic.memory_strategy_id
    role_arn    = aws_iam_role.tenant.arn
  }
}
