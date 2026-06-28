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
  enabled         = true
  comment         = "Gradio/FastAPI via ALB behind CloudFront"
  is_ipv6_enabled = true
  price_class     = "PriceClass_200"

  # ここを ALB の DNS ではなく、作成したオリジン FQDN に（SNI と Host の整合性が取れる） / Use the created origin FQDN instead of the ALB DNS name so SNI and Host match.

  origin {
    origin_id   = "alb-${aws_lb.alb.name}"
    domain_name = local.origin_fqdn

    # CloudFront -> ALB へ秘密ヘッダー / Send the secret header from CloudFront to ALB.
    custom_header {
      name  = local.cf_alb_secret_header_name
      value = random_password.cf_alb_secret_value.result
    }

    # ALB = Custom origin
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only" # HTTPS のみ       / HTTPS only.
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

  # 独自ドメイン (viewer) を紐付け / Attach the custom viewer domain.
  aliases = [var.viewer_domain_name]

  # 独自ドメインの証明書に変更 / Change to the custom domain certificate.
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cf_cert.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name = "${var.vpc_name}-cloudfront"
  }

  # CloudFront 証明書の検証が完了してから作る / Create this after CloudFront certificate validation completes
  depends_on = [aws_acm_certificate_validation.cf_cert]
}
