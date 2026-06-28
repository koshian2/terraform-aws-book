# --- ALB用SG（CloudFront からのみ80を許可）--- / Security group for ALB. Allow port 80 only from CloudFront.
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name        = "${var.vpc_name}-alb-sg"
  description = "Allow from CloudFront only"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.vpc_name}-alb-sg" }
}

# Ingress: CloudFront のオリジン向けIPから80のみ / Ingress: only port 80 from CloudFront origin-facing IPs
resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id
}

# Egress: 全許可 (IPv4) / egress: allow all IPv4 traffic
resource "aws_vpc_security_group_egress_rule" "alb_all_egress_v4" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All IPv4 egress"
}

# Egress: 全許可 (IPv6) / egress: allow all IPv6 traffic
resource "aws_vpc_security_group_egress_rule" "alb_all_egress_v6" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
  description       = "All IPv6 egress"
}

# --- ALB（インターネット向け / パブリックサブネット）--- / ALB (internet-facing / public subnet)
resource "aws_lb" "alb" {
  name               = "${var.vpc_name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnet_ids
  ip_address_type    = var.enable_ipv6 ? "dualstack" : "ipv4"

  tags = { Name = "${var.vpc_name}-alb" }
}

# --- HTTPリスナー (80) ：デフォルトは 404 応答 --- / HTTP listener (80): return 404 by default
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  # デフォルト（どのパス条件にもマッチしない場合）は 404 / The default is 404 when no path condition matches.
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found (default)"
      status_code  = "404"
    }
  }
}

# --- 固定レスポンス用ルール定義（ローカル変数）--- / Rule definitions for fixed responses in local variables
locals {
  alb_fixed_responses = [
    {
      name     = "fixed_200"
      priority = 10
      path     = "/ok"
      status   = "200"
      message  = "OK (200)"
    },
    {
      name     = "fixed_401"
      priority = 20
      path     = "/unauthorized"
      status   = "401"
      message  = "Unauthorized (401)"
    },
    {
      name     = "fixed_403"
      priority = 30
      path     = "/forbidden"
      status   = "403"
      message  = "Forbidden (403)"
    },
    {
      name     = "fixed_404"
      priority = 40
      path     = "/notfound"
      status   = "404"
      message  = "Not Found (404)"
    },
    {
      name     = "fixed_500"
      priority = 50
      path     = "/error500"
      status   = "500"
      message  = "Internal Server Error (500)"
    },
    {
      name     = "fixed_503"
      priority = 60
      path     = "/error503"
      status   = "503"
      message  = "Service Unavailable (503)"
    },
  ]
}

# --- HTTPリスナールール（固定レスポンスをループで生成）--- / Generate fixed responses in a loop.
resource "aws_lb_listener_rule" "fixed" {
  for_each = {
    for r in local.alb_fixed_responses :
    r.name => r
  }

  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = each.value.message
      status_code  = each.value.status
    }
  }

  condition {
    path_pattern {
      values = [each.value.path]
    }
  }
}
