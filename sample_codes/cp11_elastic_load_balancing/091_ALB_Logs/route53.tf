# --- Route 53 レコード ---
# Route 53（既存のパブリックホストゾーンを参照）
data "aws_route53_zone" "public" {
  name         = var.public_zone_name
  private_zone = false
}
# ワイルドカードのA/AAAA DNSレコードを追加 (*.example.com)
resource "aws_route53_record" "wild_a" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = "*.${var.public_zone_name}"
  type    = "A"
  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
resource "aws_route53_record" "wild_aaaa" {
  count   = var.enable_ipv6 ? 1 : 0
  zone_id = data.aws_route53_zone.public.zone_id
  name    = "*.${var.public_zone_name}"
  type    = "AAAA"
  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

# --- ACM 証明書（DNS 検証）: apex + wildcard を1枚で発行 ---
resource "aws_acm_certificate" "this" {
  domain_name               = var.public_zone_name          # 例: example.com
  subject_alternative_names = ["*.${var.public_zone_name}"] # 例: *.example.com
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.vpc_name}-acm"
  }
}

# 検証用のDNSレコード（apex と wildcard の両方を作成）
resource "aws_route53_record" "cert_validation" {
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
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}


