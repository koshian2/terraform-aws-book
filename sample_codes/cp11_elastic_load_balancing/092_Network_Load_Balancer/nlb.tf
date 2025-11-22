# --- NLBに割り当てるEIPをPublic Subnet数ぶん作成 ---
resource "aws_eip" "nlb" {
  for_each = toset(var.availability_zones)
  domain   = "vpc"
  tags = {
    Name = "${var.vpc_name}-nlb-eip-${replace(each.key, "ap-northeast-1", "")}"
  }
}

# --- AZ → Subnet ID の対応（AZと public_subnet_ids の順序が対応している前提）---
locals {
  az_to_subnet = {
    for idx, az in var.availability_zones :
    az => module.vpc.public_subnet_ids[idx]
  }
}

# --- NLB用セキュリティグループ ---
resource "aws_security_group" "nlb" {
  name        = "${var.vpc_name}-nlb-sg"
  description = "Allow TCP/80 from internet to NLB"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "${var.vpc_name}-nlb-sg"
  }
}

# Ingress: 80/tcp をインターネットから許可 (IPv4)
resource "aws_vpc_security_group_ingress_rule" "nlb_from_internet_ipv4" {
  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# Ingress: 80/tcp をインターネットから許可 (IPv6 / 有効なときだけ)
resource "aws_vpc_security_group_ingress_rule" "nlb_from_internet_ipv6" {
  count             = var.enable_ipv6 ? 1 : 0
  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv6         = "::/0"
}

# Egress: 全許可 (IPv4)
resource "aws_vpc_security_group_egress_rule" "nlb_egress_ipv4" {
  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Egress: 全許可 (IPv6 / 有効なときだけ)
resource "aws_vpc_security_group_egress_rule" "nlb_egress_ipv6" {
  count             = var.enable_ipv6 ? 1 : 0
  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}

# --- NLB本体（EIPをAZごとに割り当て）---
resource "aws_lb" "this" {
  name               = "${var.vpc_name}-nlb"
  load_balancer_type = "network"
  internal           = false
  ip_address_type    = var.enable_ipv6 ? "dualstack" : "ipv4"

  security_groups = [aws_security_group.nlb.id]

  # public_subnet_ids と availability_zones の個数が一致していることをチェック
  lifecycle {
    precondition {
      condition     = length(module.vpc.public_subnet_ids) == length(var.availability_zones)
      error_message = "module.vpc.public_subnet_ids と var.availability_zones の要素数が一致していません。"
    }
  }

  dynamic "subnet_mapping" {
    for_each = local.az_to_subnet
    content {
      subnet_id     = subnet_mapping.value
      allocation_id = aws_eip.nlb[subnet_mapping.key].id # 同じAZキーで参照
    }
  }

  tags = { Name = "${var.vpc_name}-nlb" }
}

# --- NLBターゲットグループ（L4: TCP/80, instanceターゲット） ---
resource "aws_lb_target_group" "web" {
  name        = "${var.vpc_name}-web-tg"
  port        = 80
  protocol    = "TCP" # L4
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  # nginx 等でHTTP疎通を見たいなら、ヘルスチェックだけHTTPにしてもOK
  health_check {
    protocol = "HTTP"
    path     = "/"
    port     = "traffic-port"
  }

  tags = { Name = "${var.vpc_name}-web-tg" }
}

# --- EC2 をターゲット登録 ---
resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web.id
  port             = 80
}

# --- NLBリスナー（TCP/80） ---
resource "aws_lb_listener" "tcp_80" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# --- 出力 ---
output "nlb_eip_ipv4_addresses" {
  value       = [for az in var.availability_zones : aws_eip.nlb[az].public_ip]
  description = "NLB IPv4 addresses (one per AZ) via EIP, ordered by var.availability_zones"
}

output "nlb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "NLB DNS name"
}