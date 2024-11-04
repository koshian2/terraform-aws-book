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
  type = string # teraform.tfvarsで規定
}

provider "aws" {
  profile = var.aws_profile_name
}

resource "aws_s3_bucket" "example" {
  bucket        = var.bucket_name
  force_destroy = true # 開発用
}

resource "aws_s3_bucket_lifecycle_configuration" "delete_after_1_day" {
  bucket = aws_s3_bucket.example.id

  rule {
    id     = "delete_after_1_day"
    status = "Enabled"

    # 全てのオブジェクトを対象
    filter {
      prefix = ""
    }

    # 1日後に完全に削除
    expiration {
      days = 1
    }

    # 未完了のマルチパートアップロードを削除
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}