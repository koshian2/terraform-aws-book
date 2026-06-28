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

# ---- CloudFront VPC Origin (ALB) ----
resource "aws_cloudfront_vpc_origin" "alb" {
  vpc_origin_endpoint_config {
    name = "${var.vpc_name}-alb-vpc-origin"

    # VPCオリジンのターゲットになる internal ALB / Internal ALB used as the VPC origin target
    arn = aws_lb.alb.arn

    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only" # 今はHTTPのみならこれでOK / This is OK when you use only HTTP for now

    origin_ssl_protocols { # HTTPS用の設定 / Settings for HTTPS
      quantity = 1
      items    = ["TLSv1.2"]
    }
  }
}


# ---- CloudFront Distribution（オリジン = VPCオリジン経由の internal ALB）---- / CloudFront distribution with an internal ALB through a VPC origin
resource "aws_cloudfront_distribution" "cdn" {
  enabled = true
  comment = "Gradio/FastAPI via internal ALB behind CloudFront VPC Origin"

  is_ipv6_enabled = true
  price_class     = "PriceClass_200"

  origin {
    origin_id   = "alb-${aws_lb.alb.name}"
    domain_name = aws_lb.alb.dns_name

    # custom_origin_config の代わりに VPCオリジン設定を紐付け / Attach VPC origin settings instead of custom_origin_config
    vpc_origin_config {
      # aws_cloudfront_vpc_origin の ID を指定 / Set the ID of aws_cloudfront_vpc_origin
      vpc_origin_id = aws_cloudfront_vpc_origin.alb.id
    }
  }

  # --- UI/動的：キャッシュ無効 + ALBクッキーをフォワード --- / UI and dynamic content: disable caching and forward the ALB cookie
  default_cache_behavior {
    target_origin_id       = "alb-${aws_lb.alb.name}"
    viewer_protocol_policy = "redirect-to-https"

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

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.vpc_name}-cloudfront"
  }
}
