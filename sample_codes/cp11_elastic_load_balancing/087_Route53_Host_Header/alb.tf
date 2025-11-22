# --- ALB用セキュリティグループ（HTTPを外部から受けるだけ） ---
resource "aws_security_group" "alb" {
  name        = "${var.vpc_name}-alb-sg"
  description = "ALB security group"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "${var.vpc_name}-alb-sg"
  }
}

# egress: 全許可 (IPv4)
resource "aws_vpc_security_group_egress_rule" "alb_all_egress_v4" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# egress: 全許可 (IPv6) ※使う場合のみ
resource "aws_vpc_security_group_egress_rule" "alb_all_egress_v6" {
  count             = var.enable_ipv6 ? 1 : 0
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}

# ingress: HTTP (IPv4)
resource "aws_vpc_security_group_ingress_rule" "alb_http_v4" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# ingress: HTTP (IPv6) ※使う場合のみ
resource "aws_vpc_security_group_ingress_rule" "alb_http_v6" {
  count             = var.enable_ipv6 ? 1 : 0
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv6         = "::/0"
}

# --- ALB本体 ---
resource "aws_lb" "this" {
  name               = "${var.vpc_name}-alb"
  load_balancer_type = "application"
  internal           = false # パブリックALB
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnet_ids
  ip_address_type    = var.enable_ipv6 ? "dualstack" : "ipv4"

  tags = {
    Name = "${var.vpc_name}-alb"
  }
}


# --- ターゲットグループ（HTTP:80 / instance ターゲット） ---
resource "aws_lb_target_group" "web" {
  name        = "${var.vpc_name}-web-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  tags = { Name = "${var.vpc_name}-web-tg" }
}

# EC2 を ターゲットグループ に登録
resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web.id
  port             = 80
}

# --- ターゲットグループ（Lambda ターゲット） ---
resource "aws_lb_target_group" "api" {
  name        = "${var.vpc_name}-tg-lambda"
  target_type = "lambda"

  # マルチバリュー・ヘッダを有効化したい場合は true（任意）
  lambda_multi_value_headers_enabled = true
}

# ALB から Lambda を呼び出す許可
resource "aws_lambda_permission" "allow_from_alb" {
  statement_id  = "AllowExecutionFromALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.arn
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.api.arn
}

# Lambda 関数をターゲットグループに登録
resource "aws_lb_target_group_attachment" "api" {
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_lambda_function.api.arn
  depends_on       = [aws_lambda_permission.allow_from_alb]
}

# --- リスナーとリスナールール（HTTP） ---
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404 Not Found"
      status_code  = "404"
    }
  }
}

# web.example.com → EC2のターゲットグループ（Web）
resource "aws_lb_listener_rule" "host_web" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 1
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  condition {
    host_header {
      values = ["web.${var.public_zone_name}"]
    }
  }
}

# api.example.com → Lambdaのターゲットグループ（API）
resource "aws_lb_listener_rule" "host_api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 2
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
  condition {
    host_header {
      values = ["api.${var.public_zone_name}"]
    }
  }
}

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
