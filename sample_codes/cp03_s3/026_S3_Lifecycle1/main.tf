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
  type = string # terraform.tfvarsで規定 / Defined in terraform.tfvars
}

provider "aws" {
  profile = var.aws_profile_name
}

resource "aws_s3_bucket" "example" {
  bucket        = var.bucket_name
  force_destroy = true # 開発用 / For development
}

# バージョニングの有効化 / Enable versioning
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
    # After 30 days since becoming non-current, keep only the latest 1 version and delete older versions
    noncurrent_version_expiration {
      noncurrent_days = 30
      newer_noncurrent_versions = 1
    }

    # 未完了のマルチパートアップロードを削除 / Delete incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }

    # 期限切れのオブジェクト削除マーカーを削除する / Delete expired object delete markers
    expiration {
      expired_object_delete_marker = true
    }
  }

  # バージョニング前提のライフサイクルなので、依存関係の明示が必要 / This lifecycle requires versioning, so explicit dependency is needed
  depends_on = [ aws_s3_bucket_versioning.versioning_enabled ]
}