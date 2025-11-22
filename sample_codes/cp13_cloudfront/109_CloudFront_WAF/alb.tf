# --- ALB用SG（CloudFront からのみ80を許可）---
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name        = "${var.vpc_name}-alb-sg"
  description = "Allow from CloudFront only"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.vpc_name}-alb-sg" }
}

# Ingress: CloudFront のオリジン向けIPから80のみ
resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id
}

# Egress: 全許可 (IPv4)
resource "aws_vpc_security_group_egress_rule" "alb_all_egress_v4" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All IPv4 egress"
}

# Egress: 全許可 (IPv6)
resource "aws_vpc_security_group_egress_rule" "alb_all_egress_v6" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
  description       = "All IPv6 egress"
}

# --- EC2(ASG)側SG：ALBからのHTTPのみ受ける（外向けは従来通り）---
resource "aws_vpc_security_group_ingress_rule" "web_from_alb" {
  security_group_id            = aws_security_group.web_instance.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
}

# --- ターゲットグループ（インスタンス登録）---
resource "aws_lb_target_group" "web" {
  name        = "${var.vpc_name}-tg-web"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  # スティッキーセッション
  stickiness {
    type            = "lb_cookie" # Application Load Balancer のLBクッキー
    cookie_duration = 3600        # 秒（例: 1時間）
    enabled         = true
  }

  health_check {
    path                = "/healthz"
    protocol            = "HTTP"
    matcher             = "200-399"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    interval            = 10
    timeout             = 5
  }

  deregistration_delay = 30
}

# --- ALB（インターネット向け / パブリックサブネット）---
resource "aws_lb" "alb" {
  name               = "${var.vpc_name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnet_ids
  ip_address_type    = var.enable_ipv6 ? "dualstack" : "ipv4"

  tags = { Name = "${var.vpc_name}-alb" }
}

# --- HTTPリスナー (80) ：デフォルトは 403 応答に ---
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  # デフォルトは403を返す（秘密ヘッダーが無いアクセスはここに落ちる）
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}

# --- 秘密ヘッダー一致時のみ フォワードする ルール（優先度1）---
resource "aws_lb_listener_rule" "allow_from_cloudfront_with_secret" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  condition {
    http_header {
      http_header_name = local.cf_alb_secret_header_name
      values           = [random_password.cf_alb_secret_value.result]
    }
  }
}
