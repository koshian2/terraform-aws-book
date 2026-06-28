# ---- マネージドポリシー（キャッシュ無効／最適化）---- / Managed policies for caching disabled and optimized caching
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# ---- ALBスティッキー用クッキーをオリジンへ送るポリシー ---- / Policy that sends the ALB sticky cookie to the origin
# ※ キャッシュキーには含めない（= Cache Policy 側で制御） / Note: Do not include it in the cache key. Control that in the cache policy.
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

  # クエリは必要に応じて / Add query strings as needed
  query_strings_config {
    query_string_behavior = "all"
  }
}

# --- 秘密ヘッダー設定（簡易：Terraformのstateに保持） --- / Secret header setting. Simple version stored in Terraform state.
locals {
  cf_alb_secret_header_name = "X-Origin-Secret"
}

resource "random_password" "cf_alb_secret_value" {
  length  = 32
  special = false
}

# ---- CloudFront Distribution（オリジン = ALB）---- / CloudFront distribution with ALB as origin
resource "aws_cloudfront_distribution" "cdn" {
  enabled = true
  comment = "Gradio/FastAPI via ALB behind CloudFront"

  # S3向けのときに使う default_root_object は付けない / Do not set default_root_object when using an S3 origin.
  # default_root_object = "index.html"

  is_ipv6_enabled = true
  price_class     = "PriceClass_200"

  origin {
    origin_id   = "alb-${aws_lb.alb.name}"
    domain_name = aws_lb.alb.dns_name

    # CloudFront から ALB へ秘密ヘッダーを常時付与 / Always add the secret header from CloudFront to ALB
    custom_header {
      name  = local.cf_alb_secret_header_name
      value = random_password.cf_alb_secret_value.result
    }

    # ALB = Custom origin
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # 本番は "https-only" を推奨（ALB側でHTTPS有効時） / Use https-only in production when HTTPS is enabled on the ALB side
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # --- UI/動的：キャッシュ無効 + ALBクッキーをフォワード --- / UI and dynamic content: disable caching and forward the ALB cookie
  default_cache_behavior {
    target_origin_id       = "alb-${aws_lb.alb.name}"
    viewer_protocol_policy = "redirect-to-https"

    # GradioはGET/HEADの他、POST/OPTIONSなども使う / Gradio uses POST and OPTIONS as well as GET and HEAD
    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    compress = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.alb_sticky_cookies.id
  }

  # --- 静的配信（例: /assets/*）：キャッシュ有効、クッキー不要 --- / Static delivery, for example /assets/*: enable caching and do not use cookies
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

  # まずはデフォルト証明書（*.cloudfront.net）で。独自ドメインは acm_certificate_arn に変更 / Start with the default *.cloudfront.net certificate. For a custom domain, change to acm_certificate_arn.
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.vpc_name}-cloudfront"
  }
}
