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

# ---- マネージドキャッシュポリシー（最適化）----
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# --- 秘密ヘッダー設定（簡易：Terraformのstateに保持） ---
locals {
  cf_alb_secret_header_name = "X-Origin-Secret"
}

resource "random_password" "cf_alb_secret_value" {
  length  = 32
  special = false
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled = true
  comment = "ALB fixed-responses + S3 error.html behind CloudFront"

  is_ipv6_enabled = true
  price_class     = "PriceClass_200"

  # ---------- オリジン1: ALB（固定レスポンス用） ----------
  origin {
    origin_id   = "alb-${aws_lb.alb.name}"
    domain_name = aws_lb.alb.dns_name

    custom_header {
      name  = local.cf_alb_secret_header_name
      value = random_password.cf_alb_secret_value.result
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # 本番は "https-only" 推奨
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ---------- オリジン2: S3（error.html 配布用） ----------
  origin {
    origin_id                = "s3-error"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  # ---------- デフォルト: ALB オリジン ----------
  default_cache_behavior {
    target_origin_id       = "alb-${aws_lb.alb.name}"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    compress        = true
    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id

    # --- Lambda@Edge: エラー時に /error.html?type=... へリダイレクト ---
    lambda_function_association {
      event_type   = "origin-response"
      lambda_arn   = aws_lambda_function.edge_error_redirect.qualified_arn
      include_body = false
    }
  }

  # ---------- /error.html* は S3 オリジンへ ----------
  ordered_cache_behavior {
    path_pattern           = "/error.html*"
    target_origin_id       = "s3-error"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    compress        = true
    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id

    # error.html では Lambda@Edge は不要（＆無限リダイレクト防止のためもこの方が安全）
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.vpc_name}-cloudfront"
  }
}
