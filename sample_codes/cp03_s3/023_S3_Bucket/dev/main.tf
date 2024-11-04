terraform {
  backend "local" {
    path = ".cache/terraform.tfstate"
  }
}

variable "aws_profile_name" {
  type    = string
  default = "develop"
}

variable "bucket_name" {
  type = string
}

provider "aws" {
  profile = var.aws_profile_name
}

# S3バケットの作成
resource "aws_s3_bucket" "example" {
  bucket        = var.bucket_name
  force_destroy = true
}
