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

resource "aws_s3_bucket_lifecycle_configuration" "move_to_glacier" {
  bucket = aws_s3_bucket.example.id

  rule {
    id     = "move_to_glacier"
    status = "Enabled"

    # archive以下のパスに限定。filterを設定しないとバケット全体
    filter {
      prefix = "archive/"
    }

    # 30日後、S3 Glacier Flexible Retrieval（storage_class="GLACIER"）に移行
    # storage_class="DEEP_ARCHIVE" : S3 Glacier Deep Archive
    # storage_class="GLACIER_IR" : S3 Glacier Instant Retrieval
    transition {
      days          = 30
      storage_class = "GLACIER"
    }
  }
}