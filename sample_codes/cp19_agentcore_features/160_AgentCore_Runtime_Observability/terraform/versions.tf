terraform {
  required_version = ">= 1.12, < 2.0"
  required_providers {
    time = { source = "hashicorp/time", version = "= 0.14.2" }
    aws  = { source = "hashicorp/aws", version = "= 6.66.0" }
  }
  backend "local" { path = "terraform.tfstate" }
}
provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
  default_tags {
    tags = { Project = "agentcore-runtime-observability", ManagedBy = "Terraform" }
  }
}
