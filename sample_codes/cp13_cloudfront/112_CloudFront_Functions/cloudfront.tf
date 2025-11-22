locals {
  # "Basic <base64(username:password)>" を作る
  basic_auth_header_value = "Basic ${base64encode("${var.basic_auth_username}:${var.basic_auth_password}")}"
}

#####################################
# CloudFront KeyValueStore（Basic Auth 用）
#####################################
resource "aws_cloudfront_key_value_store" "basic_auth" {
  name = "${local.bucket_name}-basic-auth-kvs"
}

# 上の KeyValueStore に Basic 認証用のヘッダー値を登録
resource "aws_cloudfrontkeyvaluestore_key" "basic_auth_header" {
  key_value_store_arn = aws_cloudfront_key_value_store.basic_auth.arn

  key   = "basic_auth_header"
  value = local.basic_auth_header_value
}

#####################################
# CloudFront Function (Basic Auth)
#####################################
resource "aws_cloudfront_function" "basic_auth" {
  name    = "${local.bucket_name}-basic-auth"
  comment = "Basic auth for ${local.bucket_name}"
  runtime = "cloudfront-js-2.0"
  publish = true

  code = file("${path.module}/cloudfront-basic-auth.js")

  # KeyValueStore を関連付け
  key_value_store_associations = [
    aws_cloudfront_key_value_store.basic_auth.arn
  ]
}

#---------------------------------------
# CloudFront OAC（Origin Access Control）
#---------------------------------------
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${local.bucket_name}-oac"
  description                       = "OAC for ${local.bucket_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

#---------------------------------------
# データソース: マネージドキャッシュポリシーのIDを取得
#---------------------------------------
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized" # "CachingOptimized" という名前のマネージドポリシー
}

#---------------------------------------
# CloudFront Distribution
#---------------------------------------
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  comment             = "Static site for ${local.bucket_name}"
  default_root_object = "index.html"

  origin {
    origin_id                = "s3-${aws_s3_bucket.site.bucket}"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${aws_s3_bucket.site.bucket}"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    compress = true

    # CachingOptimizedマネージドポリシー
    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id

    # ==== ここで CloudFront Function を紐付ける ====
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.basic_auth.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  price_class = "PriceClass_200"
}
