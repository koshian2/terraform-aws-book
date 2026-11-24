terraform {
  required_version = ">= 1.12, < 2.0"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "= 6.66.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.7" }
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = "ap-northeast-1"
  default_tags { tags = { Project = "guardrails-demo", ManagedBy = "Terraform" } }
}

variable "aws_profile" {
  type    = string
  default = "develop"
}

variable "model_id" {
  description = "東京から利用できるAWS提供の推論プロファイルID"
  type        = string
  default     = "jp.anthropic.claude-sonnet-4-6"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_bedrock_inference_profile" "model" {
  inference_profile_id = var.model_id
}

locals {
  name    = "guardrails-product-guide"
  account = data.aws_caller_identity.current.account_id
  prefix  = "arn:${data.aws_partition.current.partition}:bedrock"
  # 東京発のAPAC Guardrailプロファイルの宛先。モデルの推論先とは別。
  guardrail_regions = ["ap-northeast-1", "ap-northeast-2", "ap-northeast-3", "ap-south-1", "ap-southeast-1", "ap-southeast-2"]
  guardrail_profiles = [for region in local.guardrail_regions :
    "${local.prefix}:${region}:${local.account}:guardrail-profile/apac.guardrail.v1:0"
  ]
}
