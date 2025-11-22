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

# 既存のキーペアを取得（存在しないと plan 時にエラーになります）
data "aws_key_pair" "this" {
  key_name = "terraform_book_aws"
}

# 確認用の出力（任意）
output "key_name_in_use" {
  value = data.aws_key_pair.this.key_name
}