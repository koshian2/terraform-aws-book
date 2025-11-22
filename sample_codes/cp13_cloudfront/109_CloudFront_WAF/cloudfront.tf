# ---- マネージドポリシー（キャッシュ無効／最適化）----
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# ---- ALBスティッキー用クッキーをオリジンへ送るポリシー ----
# ※ キャッシュキーには含めない（= Cache Policy 側で制御）
resource "aws_cloudfront_origin_request_policy" "alb_sticky_cookies" {
  name = "${var.vpc_name}-alb-sticky-cookies"

  cookies_config {
    cookie_behavior = "whitelist"
    cookies {
      items = ["AWSALB", "AWSALBCORS"]
    }
  }

  headers_config {
    header_behavior = "none"
  }

  # クエリは必要に応じて
  query_strings_config {
    query_string_behavior = "all"
  }
}

# --- 秘密ヘッダー設定（簡易：Terraformのstateに保持） ---
locals {
  cf_alb_secret_header_name = "X-Origin-Secret"
}

resource "random_password" "cf_alb_secret_value" {
  length  = 32
  special = false
}

# ---- CloudFront Distribution（オリジン = ALB）----
resource "aws_cloudfront_distribution" "cdn" {
  enabled = true
  comment = "Gradio/FastAPI via ALB behind CloudFront"

  is_ipv6_enabled = true
  price_class     = "PriceClass_200"

  # ここを追加（WAFv2 の ARN を渡す）
  web_acl_id = aws_wafv2_web_acl.cloudfront_waf.arn

  origin {
    origin_id   = "alb-${aws_lb.alb.name}"
    domain_name = aws_lb.alb.dns_name

    # CloudFront から ALB へ秘密ヘッダーを常時付与
    custom_header {
      name  = local.cf_alb_secret_header_name
      value = random_password.cf_alb_secret_value.result
    }

    # ALB = Custom origin
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # 本番は "https-only" を推奨（ALB側でHTTPS有効時）
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # --- UI/動的：キャッシュ無効 + ALBクッキーをフォワード ---
  default_cache_behavior {
    target_origin_id       = "alb-${aws_lb.alb.name}"
    viewer_protocol_policy = "redirect-to-https"

    # GradioはGET/HEADの他、POST/OPTIONSなども使う
    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    compress = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.alb_sticky_cookies.id
  }

  # --- 静的配信（例: /assets/*）：キャッシュ有効、クッキー不要 ---
  ordered_cache_behavior {
    path_pattern           = "/assets/*"
    target_origin_id       = "alb-${aws_lb.alb.name}"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    compress = true

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  # まずはデフォルト証明書（*.cloudfront.net）で。独自ドメインは acm_certificate_arn に変更
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.vpc_name}-cloudfront"
  }
}
