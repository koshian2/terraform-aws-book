terraform {
  backend "local" {
    path = ".cache/terraform.tfstate"
  }
}

variable "aws_profile_name" {
  type    = string
  default = "develop"
}

provider "aws" {
  profile = var.aws_profile_name
}

variable "bucket_name" {
  type = string # terraform.tfvarsで規定 / Defined in terraform.tfvars
}

variable "az_id" {
  type    = string
  default = "apne1-az4"
  # ap-northeast1のリージョンのAZ4(ap-northeast-1d), 2024/10現在az1とaz4のみ対応。マネコンで要確認
  # AZ4 (ap-northeast-1d) in ap-northeast-1 region. As of Oct 2024, only az1 and az4 are supported. Verify in the management console
}

resource "aws_s3_directory_bucket" "example" {
  bucket        = "${var.bucket_name}--${var.az_id}--x-s3"
  force_destroy = true # 開発用 / For development
  location {
    name = var.az_id
  }
}
