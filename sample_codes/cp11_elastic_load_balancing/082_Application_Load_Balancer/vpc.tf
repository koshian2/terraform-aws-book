module "vpc" {
  source = "../../../modules/vpc"

  vpc_cidr_block     = var.vpc_cidr_block
  vpc_name           = var.vpc_name
  availability_zones = var.availability_zones

  assign_ipv6 = var.enable_ipv6
}

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

# 任意：ALBのDNS名を出力
output "alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "ALB DNS name"
}