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
  }

  # カスタムエラーページ設定（例: 404 を error.html に差し替え）
  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/error.html"
    error_caching_min_ttl = 10
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
