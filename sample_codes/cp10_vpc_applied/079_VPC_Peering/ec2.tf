# ---- 対象VPCのメタ（A/Bの最初のプライベートサブネット）----
locals {
  vpcs = {
    a = {
      name      = var.vpc_a_name
      vpc_id    = module.vpc_a.vpc_id
      subnet_id = module.vpc_a.private_subnet_ids[0]
      cidr_ipv4 = module.vpc_a.vpc_ipv4_cidr
      peer = {
        key       = "b"
        name      = var.vpc_b_name
        cidr_ipv4 = module.vpc_b.vpc_ipv4_cidr
      }
    }
    b = {
      name      = var.vpc_b_name
      vpc_id    = module.vpc_b.vpc_id
      subnet_id = module.vpc_b.private_subnet_ids[0]
      cidr_ipv4 = module.vpc_b.vpc_ipv4_cidr
      peer = {
        key       = "a"
        name      = var.vpc_a_name
        cidr_ipv4 = module.vpc_a.vpc_ipv4_cidr
      }
    }
  }
}


# ---- AMI（Amazon Linux 2023, x86_64）----
data "aws_ssm_parameter" "al2023_default_x86_64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---- SSM用 IAMロール/インスタンスプロフィール（A/B）----
resource "aws_iam_role" "ssm_role" {
  for_each = local.vpcs
  name     = "${each.value.name}-ec2-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = {
    Name = "${each.value.name}-ec2-ssm-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  for_each   = aws_iam_role.ssm_role
  role       = each.value.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  for_each = aws_iam_role.ssm_role
  name     = "${local.vpcs[each.key].name}-ec2-ssm-profile"
  role     = each.value.name
  tags = {
    Name = "${local.vpcs[each.key].name}-ec2-ssm-profile"
  }
}

# ---- EC2用セキュリティグループ（インバウンドは相方のVPCのHTTPを許可、全アウトバウンド許可）（A/B）----
resource "aws_security_group" "ssm_instance" {
  for_each               = local.vpcs
  name                   = "${each.value.name}-ec2-ssm-sg"
  description            = "No inbound; allow all egress for SSM over NAT"
  vpc_id                 = each.value.vpc_id
  revoke_rules_on_delete = true
  tags = {
    Name = "${each.value.name}-ec2-ssm-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "http80_from_peer" {
  for_each          = aws_security_group.ssm_instance
  security_group_id = each.value.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = local.vpcs[each.key].peer.cidr_ipv4
  description       = "Allow HTTP (80) from peer VPC CIDR"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  for_each          = aws_security_group.ssm_instance
  security_group_id = each.value.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All IPv4 egress"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  for_each          = aws_security_group.ssm_instance
  security_group_id = each.value.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
  description       = "All IPv6 egress"
}

# ---- EC2（A/Bの最初のプライベートサブネット、公開IPなし、SSM接続）----
resource "aws_instance" "ssm" {
  for_each                    = local.vpcs
  ami                         = data.aws_ssm_parameter.al2023_default_x86_64.value
  instance_type               = "t3.micro"
  subnet_id                   = each.value.subnet_id
  vpc_security_group_ids      = [aws_security_group.ssm_instance[each.key].id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ssm_profile[each.key].name

  metadata_options {
    http_tokens = "required"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    dnf -y install httpd
    systemctl enable --now httpd
    echo "Hello from $(hostname) in ${local.vpcs[each.key].name}" > /var/www/html/index.html
  EOF

  tags = {
    Name = "${each.value.name}-ec2-ssm"
  }
}

# ---- 出力（A/Bのインスタンス情報をマップで）----
data "aws_region" "current" {}

output "ssm_instances" {
  description = "EC2 info per VPC (key=a/b)"
  value = {
    for k, i in aws_instance.ssm : k => {
      id                   = i.id
      private_ip           = i.private_ip
      private_dns          = i.private_dns
      private_resource_dns = "${i.id}.${data.aws_region.current.region}.compute.internal"
    }
  }
}
