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

# ---- EC2用セキュリティグループ（全Egress許可）----
resource "aws_security_group" "web_instance" {
  name                   = "${var.vpc_name}-ec2-web-sg"
  description            = "No inbound; allow all egress for SSM over NAT"
  vpc_id                 = module.vpc.vpc_id
  revoke_rules_on_delete = true
  tags = {
    Name = "${var.vpc_name}-ec2-web-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.web_instance.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All IPv4 egress (via NAT GW)"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  security_group_id = aws_security_group.web_instance.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
  description       = "All IPv6 egress (via Egress-only IGW)"
}

# ---- AMI（Amazon Linux 2023, x86_64）----
data "aws_ssm_parameter" "al2023_default_x86_64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# --- 起動テンプレート（元の aws_instance web を置き換え） ---
resource "aws_launch_template" "web" {
  name_prefix   = "${var.vpc_name}-lt-web-"
  image_id      = data.aws_ssm_parameter.al2023_default_x86_64.value
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ssm_profile.name
  }

  # サブネットはAuto Scaling Group側で指定するため、ここでは指定しない
  network_interfaces {
    # パブリックIPは付与しない（プライベートサブネット前提）
    associate_public_ip_address = false
    security_groups             = [aws_security_group.web_instance.id]
  }

  metadata_options {
    http_tokens = "required"
  }

  # user_data は base64 エンコード文字列
  user_data = base64encode(<<-EOT
    #!/bin/bash -xe
    dnf -y update
    dnf -y install nginx
    systemctl enable --now nginx
    systemctl enable --now amazon-ssm-agent
    echo "hello from $(hostname -f)" > /usr/share/nginx/html/index.html
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.vpc_name}-ec2-web"
    }
  }

  # デフォルト版を更新する（任意）
  update_default_version = true
}


# 起動テンプレートからEC2を立ち上げ
resource "aws_instance" "web_from_lt" {
  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest" # もしくは固定の番号
  }

  # 起動テンプレートの値を上書き可能
  subnet_id                   = module.vpc.private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.web_instance.id]
  associate_public_ip_address = false
}