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
    tags = { Project = "agentcore-memory-strategies", ManagedBy = "Terraform" }
  }
}

# 会話イベントを7日間保持する。
resource "aws_bedrockagentcore_memory" "demo" {
  name                  = "conversation_strategies"
  description           = "Compare built-in Semantic, User Preference, Summary and Episodic strategies"
  event_expiry_duration = 7
}
