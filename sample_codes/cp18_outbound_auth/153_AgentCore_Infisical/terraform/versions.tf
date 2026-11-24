terraform {
  required_version = ">= 1.11, < 2.0"
  required_providers {
    time = { source = "hashicorp/time", version = "= 0.14.2" }
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.66.0"
    }
    infisical = {
      source  = "Infisical/infisical"
      version = "= 0.19.33"
    }
  }
  backend "local" { path = "terraform.tfstate" }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
  default_tags {
    tags = { Project = "agentcore-mcp-infisical", ManagedBy = "Terraform" }
  }
}



# AWS_PROFILE must also be set for Infisical's independent AWS SDK.
provider "infisical" {
  host = var.infisical_host
  auth = { aws_iam = { identity_id = var.infisical_manager_identity_id } }
}
