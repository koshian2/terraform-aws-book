terraform {
  required_version = ">= 1.12, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "= 6.66.0" }
  }
  backend "local" { path = "terraform.tfstate" }
}
provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
  default_tags { tags = { Project = "cognito-web-login", ManagedBy = "Terraform" } }
}
data "aws_partition" "current" {}
variable "aws_profile" {
  type    = string
  default = "develop"
}
variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}
locals {
  site_url = "https://${aws_cloudfront_distribution.web.domain_name}/"
  issuer   = "https://cognito-idp.${var.aws_region}.${data.aws_partition.current.dns_suffix}/${aws_cognito_user_pool.users.id}"
  domain   = "https://${aws_cognito_user_pool_domain.login.domain}.auth.${var.aws_region}.amazoncognito.com"
}
