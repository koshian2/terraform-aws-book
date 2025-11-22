data "aws_route53_zone" "this" {
  name         = var.hosted_zone_name # 例: "example.com."
  private_zone = false
}

# ALB を指すオリジン FQDN（例: origin.example.com）
locals {
  origin_fqdn = "${var.origin_subdomain}.${trimsuffix(var.hosted_zone_name, ".")}"
}

# A/AAAA (ALIAS) で ALB を指す
resource "aws_route53_record" "origin_alias_a" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.origin_fqdn
  type    = "A"
  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "origin_alias_aaaa" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.origin_fqdn
  type    = "AAAA"
  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = false
  }
}

# CloudFront に向ける viewer 用ドメイン (例: web.example.com)
# var.viewer_domain_name = "web.example.com"
resource "aws_route53_record" "viewer_alias_a" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.viewer_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "viewer_alias_aaaa" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.viewer_domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}
