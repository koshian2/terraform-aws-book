# --- ALB用セキュリティグループ（HTTPを外部から受けるだけ） ---
resource "aws_security_group" "alb" {
  name        = "${var.vpc_name}-alb-sg"
  description = "ALB security group"
  vpc_id      = module.vpc.vpc_id

  tags = { Name = "${var.vpc_name}-alb-sg" }
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
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnet_ids
  ip_address_type    = var.enable_ipv6 ? "dualstack" : "ipv4"

  tags = { Name = "${var.vpc_name}-alb" }
}

# --- ターゲットグループ（HTTP:80 / instance ターゲット） ---
resource "aws_lb_target_group" "web" {
  name        = "${var.vpc_name}-web-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/health"
    port                = "traffic-port"
    matcher             = "200-299"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
  }

  tags = { Name = "${var.vpc_name}-web-tg" }
}

# --- リスナー（HTTP）: デフォルトで ASG 配下の TG へフォワード ---
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# --- 任意：ALBのDNS名を出力 ---
output "alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "ALB DNS name"
}
