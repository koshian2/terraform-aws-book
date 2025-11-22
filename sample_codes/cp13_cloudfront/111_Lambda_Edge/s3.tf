#---------------------------------------
# ランダムサフィックスでバケット名を一意化
#---------------------------------------
resource "random_id" "bucket" {
  byte_length = 4
}

locals {
  bucket_name = "${var.bucket_name_prefix}-${random_id.bucket.hex}"
  error_file  = "${abspath(var.site_dir)}/error.html"
}

#---------------------------------------
# S3 バケット（パブリックブロック＋OAC 経由のみアクセス）
#---------------------------------------
resource "aws_s3_bucket" "site" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }  
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#---------------------------------------
# error.html だけアップロード
#---------------------------------------
resource "aws_s3_object" "error" {
  bucket        = aws_s3_bucket.site.id
  key           = "error.html"
  source        = local.error_file
  etag          = filemd5(local.error_file)
  content_type  = "text/html"
  cache_control = "no-cache"
}

#---------------------------------------
# S3 バケットポリシー（CloudFront からの GetObject と ListBucket のみ許可）
# ＊OAC の推奨形式：SourceArn に Distribution ARN を条件指定
#---------------------------------------
resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid : "AllowCloudFrontServicePrincipalReadOnly",
        Effect : "Allow",
        Principal : { Service : "cloudfront.amazonaws.com" },
        Action = ["s3:GetObject", "s3:ListBucket"],
        Resource = [
          aws_s3_bucket.site.arn,
          "${aws_s3_bucket.site.arn}/*"
        ],
        Condition : {
          StringEquals : {
            "AWS:SourceArn" : aws_cloudfront_distribution.cdn.arn
          }
        }
      }
    ]
  })
}
