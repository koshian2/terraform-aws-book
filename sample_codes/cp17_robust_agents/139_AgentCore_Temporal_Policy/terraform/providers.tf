terraform {
  required_version = ">= 1.12, < 2.0"
  required_providers {
    aws  = { source = "hashicorp/aws", version = "= 6.66.0" }
    time = { source = "hashicorp/time", version = "~> 0.13" }
  }
  backend "local" { path = "terraform.tfstate" }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
  default_tags { tags = { Project = "agentcore-temporal-policy", ManagedBy = "Terraform" } }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
