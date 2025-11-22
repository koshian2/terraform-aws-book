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

# 生成した公開鍵(.pub)へのパス
variable "public_key_path" {
  type        = string
  description = "Path to your ed25519 public key (.pub)"
  # デフォルトは Linux/macOS 用。Windows でも '~/.ssh/...' で OK（pathexpand が展開）
  default = "~/.ssh/aws/terraform_book/terraform_book_local_ed25519.pub"
}

# AWS 上のキーペア名
variable "key_name" {
  type    = string
  default = "terraform_book_local"
}

resource "aws_key_pair" "this" {
  key_name   = var.key_name
  public_key = file(pathexpand(var.public_key_path))

  tags = {
    Name = var.key_name
  }
}

output "key_pair_name" {
  value = aws_key_pair.this.key_name
}