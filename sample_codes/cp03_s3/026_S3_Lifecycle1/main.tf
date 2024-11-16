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
  type = string # terraform.tfvarsで規定
}

provider "aws" {
  profile = var.aws_profile_name
}

resource "aws_s3_bucket" "example" {
  bucket        = var.bucket_name
  force_destroy = true # 開発用
}

# バージョニングの有効化
resource "aws_s3_bucket_versioning" "versioning_enabled" {
  bucket = aws_s3_bucket.example.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "versioning_config" {
  bucket = aws_s3_bucket.example.id

  rule {
    id     = "remove_old_version"
    status = "Enabled"

    # 最新バージョンでなくなってから、30日間経過したら最新の1バージョンのみ保持し、昔のバージョンを削除する
    noncurrent_version_expiration {
      noncurrent_days = 30
      newer_noncurrent_versions = 1
    }

    # 未完了のマルチパートアップロードを削除
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }

    # 期限切れのオブジェクト削除マーカーを削除する
    expiration {
      expired_object_delete_marker = true
    }
  }

  # バージョニング前提のライフサイクルなので、依存関係の明示が必要
  depends_on = [ aws_s3_bucket_versioning.versioning_enabled ]
}