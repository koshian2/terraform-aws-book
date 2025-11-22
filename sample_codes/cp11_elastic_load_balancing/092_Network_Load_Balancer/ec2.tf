# ---- SSM用 IAMロール & インスタンスプロフィール ----
resource "aws_iam_role" "ssm_role" {
  name = "${var.vpc_name}-ec2-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = {
    Name = "${var.vpc_name}-ec2-ssm-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "${var.vpc_name}-ec2-ssm-profile"
  role = aws_iam_role.ssm_role.name
  tags = {
    Name = "${var.vpc_name}-ec2-ssm-profile"
  }
}

# ---- EC2用SG（インバウンド: 80/TCP は NLB SG からのみ、アウトバウンド: 全許可）----
resource "aws_security_group" "web_instance" {
  name                   = "${var.vpc_name}-ec2-web-sg"
  description            = "Allow HTTP from NLB; egress all (SSM/NAT)"
  vpc_id                 = module.vpc.vpc_id
  revoke_rules_on_delete = true
  tags                   = { Name = "${var.vpc_name}-ec2-web-sg" }
}

# Ingress: NLB の SG からの 80/TCP のみ許可（IPv4/IPv6 共通）
resource "aws_vpc_security_group_ingress_rule" "web_http_from_nlb" {
  security_group_id            = aws_security_group.web_instance.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.nlb.id
  description                  = "Allow HTTP from NLB security group only"
}

# egress: 全許可 (IPv4)
resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.web_instance.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All IPv4 egress"
}

# egress: 全許可 (IPv6)
resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  security_group_id = aws_security_group.web_instance.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
  description       = "All IPv6 egress"
}

# ---- AMI（Amazon Linux 2023, x86_64）----
data "aws_ssm_parameter" "al2023_default_x86_64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---- EC2（プライベートサブネット。公開IPなし、SSM接続）----
resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.al2023_default_x86_64.value
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc.private_subnet_ids[0]
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
    Name = "${var.vpc_name}-ec2-web"
  }
}
