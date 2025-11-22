# (1) VPC A: 内部 NLB と Target Group
# --- NLB用 SG（A VPC 内）
resource "aws_security_group" "a_nlb_sg" {
  name        = "${var.vpc_a_name}-nlb-sg"
  description = "Security group for internal NLB"
  vpc_id      = module.vpc_a.vpc_id
  tags = { Name = "${var.vpc_a_name}-nlb-sg" }
}

# 受け口: VPCE→NLBへのTCP/80（基本は広く受け、細かく絞るならVPCE側の送信元で制御）
resource "aws_vpc_security_group_ingress_rule" "a_nlb_ingress_80" {
  security_group_id = aws_security_group.a_nlb_sg.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow TCP/80 to NLB (filtered by VPCE SG on the client side)"
}

# 送信は既定(All egress)でOK
resource "aws_vpc_security_group_egress_rule" "a_nlb_egress_all" {
  security_group_id = aws_security_group.a_nlb_sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- NLB (internal) ---
resource "aws_lb" "a_nlb" {
  name               = "${var.vpc_a_name}-nlb"
  load_balancer_type = "network"
  internal           = true
  subnets            = module.vpc_a.private_subnet_ids
  security_groups    = [aws_security_group.a_nlb_sg.id]

  tags = {
    Name = "${var.vpc_a_name}-nlb"
  }
}

# --- Target Group (TCP:80) ---
resource "aws_lb_target_group" "a_tg" {
  name        = "${var.vpc_a_name}-tg-80"
  port        = 80
  protocol    = "TCP"
  vpc_id      = module.vpc_a.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = {
    Name = "${var.vpc_a_name}-tg-80"
  }
}

# --- Listener (TCP:80) ---
resource "aws_lb_listener" "a_nlb_80" {
  load_balancer_arn = aws_lb.a_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.a_tg.arn
  }
}

# --- A 側 EC2 を TG に登録 ---
resource "aws_lb_target_group_attachment" "a_ec2_attach" {
  target_group_arn = aws_lb_target_group.a_tg.arn
  target_id        = aws_instance.ssm["a"].id
  port             = 80
}

# (2) VPC A: Endpoint Service（PrivateLink サービス側）
data "aws_caller_identity" "current" {}

resource "aws_vpc_endpoint_service" "a_service" {
  acceptance_required = false  # 同アカウント内接続を自動承認
  network_load_balancer_arns = [
    aws_lb.a_nlb.arn
  ]

  tags = {
    Name = "${var.vpc_a_name}-vpce-svc"
  }
}

# 同一アカウントを許可（同アカウント内の VPC から作る Interface Endpoint を許容）
resource "aws_vpc_endpoint_service_allowed_principal" "a_service_allow_self" {
  vpc_endpoint_service_id = aws_vpc_endpoint_service.a_service.id
  principal_arn           = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
}

# (3) VPC B: Interface VPC Endpoint（クライアント側）
# Endpoint ENI 用 SG（B 内から 80/TCP を許可）
resource "aws_security_group" "b_vpce_sg" {
  name        = "${var.vpc_b_name}-vpce-sg"
  description = "Interface VPC Endpoint ENI SG"
  vpc_id      = module.vpc_b.vpc_id
  tags = {
    Name = "${var.vpc_b_name}-vpce-sg"
  }
}

# EC2 BからのSGを参照して許可
resource "aws_vpc_security_group_ingress_rule" "b_vpce_ingress_80_from_vpc_b" {
  security_group_id            = aws_security_group.b_vpce_sg.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.ssm_instance["b"].id
  description                  = "Allow TCP/80 from EC2 B SG to the Interface Endpoint"
}

resource "aws_vpc_security_group_egress_rule" "b_vpce_all_egress" {
  security_group_id = aws_security_group.b_vpce_sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All egress from Interface Endpoint"
}

# Interface Endpoint 本体
resource "aws_vpc_endpoint" "b_to_a_service" {
  vpc_id              = module.vpc_b.vpc_id
  service_name        = aws_vpc_endpoint_service.a_service.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc_b.private_subnet_ids
  security_group_ids  = [aws_security_group.b_vpce_sg.id]
  private_dns_enabled = false  # 独自 Private DNS 名を使う場合は別途検証・設定が必要

  tags = {
    Name = "${var.vpc_b_name}-to-${var.vpc_a_name}-vpce"
  }
}

# (4) 出力
output "privatelink" {
  description = "PrivateLink接続情報: エンドポイントサービス名、VPCエンドポイントID、DNS名など"
  value = {
    endpoint_service_name = aws_vpc_endpoint_service.a_service.service_name
    endpoint_id           = aws_vpc_endpoint.b_to_a_service.id
    endpoint_dns_names    = aws_vpc_endpoint.b_to_a_service.dns_entry[*].dns_name
    nlb_dns_name          = aws_lb.a_nlb.dns_name
  }
}
