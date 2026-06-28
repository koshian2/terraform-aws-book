# --- NLBに割り当てるEIPをPublic Subnet数ぶん作成 --- / Create one EIP per public subnet for the NLB
resource "aws_eip" "nlb" {
  for_each = toset(var.availability_zones)
  domain   = "vpc"
  tags = {
    Name = "${var.vpc_name}-nlb-eip-${replace(each.key, "ap-northeast-1", "")}"
  }
}

# --- AZ → Subnet ID の対応（AZと public_subnet_ids の順序が対応している前提）--- / AZ to subnet ID mapping. Assumes AZs and public_subnet_ids are in the same order.
locals {
  az_to_subnet = {
    for idx, az in var.availability_zones :
    az => module.vpc.public_subnet_ids[idx]
  }
}

# --- NLB用セキュリティグループ --- / Security group for NLB
resource "aws_security_group" "nlb" {
  name        = "${var.vpc_name}-nlb-sg"
  description = "Allow TCP/80 from internet to NLB"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "${var.vpc_name}-nlb-sg"
  }
}

# Ingress: 80/tcp をインターネットから許可 (IPv4) / Allow 80/tcp from the internet.
resource "aws_vpc_security_group_ingress_rule" "nlb_from_internet_ipv4" {
  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# Ingress: 80/tcp をインターネットから許可 (IPv6 / 有効なときだけ) / Only when IPv6 is enabled.
resource "aws_vpc_security_group_ingress_rule" "nlb_from_internet_ipv6" {
  count             = var.enable_ipv6 ? 1 : 0
  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv6         = "::/0"
}

# Egress: 全許可 (IPv4) / egress: allow all IPv4 traffic
resource "aws_vpc_security_group_egress_rule" "nlb_egress_ipv4" {
  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Egress: 全許可 (IPv6 / 有効なときだけ) / Only when IPv6 is enabled.
resource "aws_vpc_security_group_egress_rule" "nlb_egress_ipv6" {
  count             = var.enable_ipv6 ? 1 : 0
  security_group_id = aws_security_group.nlb.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}

# --- NLB本体（EIPをAZごとに割り当て）--- / NLB resource. Assign EIPs per AZ.
resource "aws_lb" "this" {
  name               = "${var.vpc_name}-nlb"
  load_balancer_type = "network"
  internal           = false
  ip_address_type    = var.enable_ipv6 ? "dualstack" : "ipv4"

  security_groups = [aws_security_group.nlb.id]

  # public_subnet_ids と availability_zones の個数が一致していることをチェック / Check that public_subnet_ids and availability_zones have the same number of elements.
  lifecycle {
    precondition {
      condition     = length(module.vpc.public_subnet_ids) == length(var.availability_zones)
      error_message = "module.vpc.public_subnet_ids と var.availability_zones の要素数が一致していません。 / The number of elements in module.vpc.public_subnet_ids and var.availability_zones does not match."
    }
  }

  dynamic "subnet_mapping" {
    for_each = local.az_to_subnet
    content {
      subnet_id     = subnet_mapping.value
      allocation_id = aws_eip.nlb[subnet_mapping.key].id # 同じAZキーで参照 / Reference by the same AZ key.
    }
  }

  tags = { Name = "${var.vpc_name}-nlb" }
}

# --- NLBターゲットグループ（L4: TCP/80, instanceターゲット） --- / NLB target group for L4 TCP/80 with instance targets.
resource "aws_lb_target_group" "web" {
  name        = "${var.vpc_name}-web-tg"
  port        = 80
  protocol    = "TCP" # L4
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  # nginx 等でHTTP疎通を見たいなら、ヘルスチェックだけHTTPにしてもOK / If you want to check HTTP connectivity with nginx or similar, using HTTP only for health checks is OK.
  health_check {
    protocol = "HTTP"
    path     = "/"
    port     = "traffic-port"
  }

  tags = { Name = "${var.vpc_name}-web-tg" }
}

# --- EC2 をターゲット登録 --- / Register EC2 as a target
resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web.id
  port             = 80
}

# --- NLBリスナー（TCP/80） --- / NLB listener on TCP/80
resource "aws_lb_listener" "tcp_80" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# --- 出力 --- / Outputs
output "nlb_eip_ipv4_addresses" {
  value       = [for az in var.availability_zones : aws_eip.nlb[az].public_ip]
  description = "NLB IPv4 addresses (one per AZ) via EIP, ordered by var.availability_zones"
}

output "nlb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "NLB DNS name"
}