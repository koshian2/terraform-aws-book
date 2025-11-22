# 一意なバケット名が必要
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  app_bucket_name = "${var.vpc_name}-gradio-app-${random_id.suffix.hex}"
  app_prefix      = "app" # s3://bucket/app/...
}

resource "aws_s3_bucket" "app" {
  bucket        = local.app_bucket_name
  force_destroy = true
  tags          = { Name = local.app_bucket_name }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }  
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "app" {
  bucket = aws_s3_bucket.app.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id
  versioning_configuration { status = "Enabled" }
}

# 置きたい3ファイルをアップロード（ローカルの既存ファイルを利用）
resource "aws_s3_object" "requirements" {
  bucket       = aws_s3_bucket.app.bucket
  key          = "${local.app_prefix}/requirements.txt"
  source       = "${path.module}/../../apps/gradio_image_classification/requirements.txt"
  etag         = filemd5("${path.module}/../../apps/gradio_image_classification/requirements.txt")
  content_type = "text/plain"
}

resource "aws_s3_object" "app_py" {
  bucket = aws_s3_bucket.app.bucket
  key    = "${local.app_prefix}/app.py"
  source = "${path.module}/../../apps/gradio_image_classification/app.py"
  etag   = filemd5("${path.module}/../../apps/gradio_image_classification/app.py")
}

resource "aws_s3_object" "service" {
  bucket       = aws_s3_bucket.app.bucket
  key          = "${local.app_prefix}/gradio.service"
  source       = "${path.module}/../../apps/gradio_image_classification/gradio.service"
  etag         = filemd5("${path.module}/../../apps/gradio_image_classification/gradio.service")
  content_type = "text/plain"
}
