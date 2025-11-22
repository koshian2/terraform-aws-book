# --- ALB (internal) セキュリティグループ in web VPC ---
resource "aws_security_group" "alb" {
  name        = "${var.web_vpc_name}-alb-sg"
  description = "Internal ALB SG (only from VPN VPC)"
  vpc_id      = module.vpc_web.vpc_id
  tags = {
    Name = "${var.web_vpc_name}-alb-sg"
  }
}

# egress: 全許可
resource "aws_vpc_security_group_egress_rule" "alb_all_egress_v4" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_all_egress_v6" {
  count             = var.enable_ipv6 ? 1 : 0
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}

# ingress: HTTP 80(リダイレクト用) + HTTPS 443(実トラフィック) ← どちらも VPN VPC からのみ
resource "aws_vpc_security_group_ingress_rule" "alb_http_from_vpn_v4" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = module.vpc_vpn.vpc_ipv4_cidr
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_from_vpn_v6" {
  count             = var.enable_ipv6 ? 1 : 0
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv6         = module.vpc_vpn.vpc_ipv6_cidr
}

resource "aws_vpc_security_group_ingress_rule" "alb_https_from_vpn_v4" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = module.vpc_vpn.vpc_ipv4_cidr
}

resource "aws_vpc_security_group_ingress_rule" "alb_https_from_vpn_v6" {
  count             = var.enable_ipv6 ? 1 : 0
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = module.vpc_vpn.vpc_ipv6_cidr
}

# --- 内部ALB本体 ---
resource "aws_lb" "this" {
  name               = "${var.web_vpc_name}-alb"
  load_balancer_type = "application"
  internal           = true # ← この一行でALBが「内部用」になる
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc_web.private_subnet_ids
  ip_address_type    = var.enable_ipv6 ? "dualstack" : "ipv4"

  tags = {
    Name = "${var.web_vpc_name}-internal-alb"
  }
}

# --- ターゲットグループ（HTTP:80 / instance ターゲット） ---
resource "aws_lb_target_group" "web" {
  name        = "${var.web_vpc_name}-web-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc_web.vpc_id
  target_type = "instance"

  tags = { Name = "${var.web_vpc_name}-web-tg" }
}

resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web.id
  port             = 80
}

# --- ターゲットグループ（Lambda ターゲット） ---
resource "aws_lb_target_group" "api" {
  name        = "${var.web_vpc_name}-tg-lambda"
  target_type = "lambda"

  lambda_multi_value_headers_enabled = true
}

resource "aws_lambda_permission" "allow_from_alb" {
  statement_id  = "AllowExecutionFromALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.arn
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.api.arn
}

resource "aws_lb_target_group_attachment" "api" {
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_lambda_function.api.arn
  depends_on       = [aws_lambda_permission.allow_from_alb]
}

# --- HTTP(80) → HTTPS(443) へ恒久リダイレクト（HTTP） ---
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# --- リスナーとリスナールール（HTTPS） ---
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
  certificate_arn   = aws_acm_certificate.this.arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404 Not Found"
      status_code  = "404"
    }
  }

  depends_on = [aws_acm_certificate_validation.this]
}

# web.intra.example.com → EC2のターゲットグループ（Web）
resource "aws_lb_listener_rule" "host_web" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 1
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  condition {
    host_header {
      values = ["web.${var.private_zone_name}"]
    }
  }
}

# api.intra.example.com → Lambdaのターゲットグループ（API）
resource "aws_lb_listener_rule" "host_api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 2
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
  condition {
    host_header {
      values = ["api.${var.private_zone_name}"]
    }
  }
}

# --- Outputs ---
output "internal_alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "Internal ALB DNS name (AWS-provided)"
}
output "private_fqdns" {
  value = {
    web = "web.${var.private_zone_name}"
    api = "api.${var.private_zone_name}"
  }
  description = "Private FQDNs in PHZ"
}

