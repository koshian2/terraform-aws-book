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
    tags = { Project = "agentcore-memory-basic", ManagedBy = "Terraform" }
  }
}

# 会話イベントを7日間保持する。
resource "aws_bedrockagentcore_memory" "demo" {
  name                  = "conversation_memory"
  description           = "Explicit conversation storage and retrieval from local Python"
  event_expiry_duration = 7
}

output "client_config" {
  value = {
    aws_profile = var.aws_profile
    aws_region  = var.aws_region
    memory_id   = aws_bedrockagentcore_memory.demo.id
    model_id    = var.model_id
  }
}
