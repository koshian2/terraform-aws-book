#---------------------------------------
# ランダムサフィックスでバケット名を一意化
#---------------------------------------
resource "random_id" "bucket" {
  byte_length = 4
}

locals {
  bucket_name    = "${var.bucket_name_prefix}-${random_id.bucket.hex}"
  index_file     = "${abspath(var.site_dir)}/index.html"
  img_venue_file = "${abspath(var.site_dir)}/conference-venue.jpeg"
  img_hero_file  = "${abspath(var.site_dir)}/hero-background.jpeg"
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
# 静的コンテンツをアップロード
#---------------------------------------
resource "aws_s3_object" "index" {
  bucket        = aws_s3_bucket.site.id
  key           = "index.html"
  source        = local.index_file
  etag          = filemd5(local.index_file)
  content_type  = "text/html"
  cache_control = "no-cache"
}

resource "aws_s3_object" "img_venue" {
  bucket        = aws_s3_bucket.site.id
  key           = "conference-venue.jpeg"
  source        = local.img_venue_file
  etag          = filemd5(local.img_venue_file)
  content_type  = "image/jpeg"
  cache_control = "public, max-age=31536000, immutable"
}

resource "aws_s3_object" "img_hero" {
  bucket        = aws_s3_bucket.site.id
  key           = "hero-background.jpeg"
  source        = local.img_hero_file
  etag          = filemd5(local.img_hero_file)
  content_type  = "image/jpeg"
  cache_control = "public, max-age=31536000, immutable"
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
