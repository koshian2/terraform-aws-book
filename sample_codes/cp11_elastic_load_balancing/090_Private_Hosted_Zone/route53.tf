# --- Route 53 レコード ---
# Route 53（既存のパブリックホストゾーンを参照）
data "aws_route53_zone" "public" {
  name         = var.public_zone_name
  private_zone = false
}

# --- ACM 証明書（パブリックホストゾーン経由のDNS 検証）---
# --- intra + wildcard を1枚で発行 ---
resource "aws_acm_certificate" "this" {
  domain_name               = var.private_zone_name          # 例: intra.example.com
  subject_alternative_names = ["*.${var.private_zone_name}"] # 例: *.intra.example.com
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# 検証 CNAME は Public Hosted Zone に作成
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = data.aws_route53_zone.public.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}

# --- プライベートホストゾーン（各VPCに配置）---
resource "aws_route53_zone" "private" {
  name = var.private_zone_name
  vpc {
    vpc_id = module.vpc_web.vpc_id
  }
  comment = "Private hosted zone for internal ALB"
  tags    = { Name = var.private_zone_name }
}

data "aws_region" "current" {}

# VPN VPC からも解決できるよう関連付け
resource "aws_route53_zone_association" "private_vpn" {
  zone_id    = aws_route53_zone.private.zone_id
  vpc_id     = module.vpc_vpn.vpc_id
  vpc_region = data.aws_region.current.region # リージョン指定が重要
}

# ワイルドカードのA/AAAA DNSレコードを追加 (*.intra.example.com)
resource "aws_route53_record" "wild_a" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "*.${var.private_zone_name}"
  type    = "A"
  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
resource "aws_route53_record" "wild_aaaa" {
  count   = var.enable_ipv6 ? 1 : 0
  zone_id = aws_route53_zone.private.zone_id
  name    = "*.${var.private_zone_name}"
  type    = "AAAA"
  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
