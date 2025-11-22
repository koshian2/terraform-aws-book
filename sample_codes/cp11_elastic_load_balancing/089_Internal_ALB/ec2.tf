# ---- SSM用 IAMロール & インスタンスプロフィール ----
resource "aws_iam_role" "ssm_role" {
  name = "ec2-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = {
    Name = "ec2-ssm-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "ec2-ssm-profile"
  role = aws_iam_role.ssm_role.name
  tags = {
    Name = "ec2-ssm-profile"
  }
}

# ---- EC2用セキュリティグループ（ALBからのHTTP許可、全Egress許可）----
resource "aws_security_group" "web_instance" {
  name                   = "${var.web_vpc_name}-ec2-web-sg"
  description            = "Allow HTTP only from ALB SG; egress all"
  vpc_id                 = module.vpc_web.vpc_id
  revoke_rules_on_delete = true
  tags = {
    Name = "${var.web_vpc_name}-ec2-web-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "http_from_alb" {
  security_group_id            = aws_security_group.web_instance.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "web_all_ipv4" {
  security_group_id = aws_security_group.web_instance.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All IPv4 egress (via NAT GW)"
}

resource "aws_vpc_security_group_egress_rule" "web_all_ipv6" {
  count             = var.enable_ipv6 ? 1 : 0
  security_group_id = aws_security_group.web_instance.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}

# ---- AMI（Amazon Linux 2023, x86_64）----
data "aws_ssm_parameter" "al2023_default_x86_64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---- EC2（プライベートサブネット。公開IPなし、SSM接続）----
resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.al2023_default_x86_64.value
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc_web.private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.web_instance.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ssm_profile.name

  metadata_options {
    http_tokens = "required"
  }

  user_data = <<-EOF
    #!/bin/bash -xe
    dnf -y update
    dnf -y install nginx
    systemctl enable --now nginx

    # 念のため SSM Agent 有効化（AL2023 は基本インストール済）
    systemctl enable --now amazon-ssm-agent

    echo "hello from $(hostname -f)" > /usr/share/nginx/html/index.html
  EOF

  tags = {
    Name = "${var.web_vpc_name}-ec2-web"
  }
}

# ---- VPN EC2 (vpc_vpn / private / SSM接続のみ)----
resource "aws_security_group" "vpn_client" {
  name                   = "${var.vpn_vpc_name}-ec2-vpn-sg"
  description            = "No inbound; egress all for SSM/NAT"
  vpc_id                 = module.vpc_vpn.vpc_id
  revoke_rules_on_delete = true
  tags                   = { Name = "${var.vpn_vpc_name}-ec2-vpn-sg" }
}

resource "aws_vpc_security_group_egress_rule" "vpn_all_ipv4" {
  security_group_id = aws_security_group.vpn_client.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "vpn_all_ipv6" {
  count             = var.enable_ipv6 ? 1 : 0
  security_group_id = aws_security_group.vpn_client.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}

resource "aws_instance" "vpn_client" {
  ami                         = data.aws_ssm_parameter.al2023_default_x86_64.value
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc_vpn.private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.vpn_client.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ssm_profile.name
  metadata_options { http_tokens = "required" }

  user_data = <<-EOF
    #!/bin/bash -xe
    dnf -y update
    dnf -y install curl jq
    systemctl enable --now amazon-ssm-agent
  EOF

  tags = {
    Name = "${var.vpn_vpc_name}-ec2-vpn-client"
  }
}