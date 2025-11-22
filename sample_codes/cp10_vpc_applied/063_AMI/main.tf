terraform {
  backend "local" {
    path = ".cache/terraform.tfstate"
  }

  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.8.0"
    }
  }  
}

variable "aws_profile_name" {
  type    = string
  default = "develop"
}

provider "aws" {
  profile = var.aws_profile_name
}

# OS (Arch) => SSM パラメータ名
locals {
  ami_params = {
    "Ubuntu 24.04 (x86_64)"      = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
    "Ubuntu 24.04 (arm64)"       = "/aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id"
    "Amazon Linux 2023 (x86_64)" = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    "Amazon Linux 2023 (arm64)"  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
  }
}

data "aws_ssm_parameter" "ami" {
  for_each = local.ami_params
  name     = each.value
}

# 出力: "OS (Arch)" => AMI ID
output "ami_ids" {
  description = "Map of \"OS (Arch)\" => AMI ID"
  value = {
    for key, param in data.aws_ssm_parameter.ami :
    key => nonsensitive(param.value) # プロバイダ側で常に sensitive 扱い。公開AMI IDなのでOK
  }
}