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

# ---- EC2用セキュリティグループ（インバウンド0、全Egress許可）----
resource "aws_security_group" "ssm_instance" {
  name                   = "${var.vpc_name}-ec2-ssm-sg"
  description            = "No inbound; allow all egress for SSM over NAT"
  vpc_id                 = aws_vpc.main.id
  revoke_rules_on_delete = true
  tags = {
    Name = "${var.vpc_name}-ec2-ssm-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.ssm_instance.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All IPv4 egress (via NAT GW)"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  security_group_id = aws_security_group.ssm_instance.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
  description       = "All IPv6 egress (via Egress-only IGW)"
}

# ---- AMI（Amazon Linux 2023, x86_64）----
data "aws_ssm_parameter" "al2023_default_x86_64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---- オプション：既存のキーペア（Session Manager本来は不要） ----
data "aws_key_pair" "this" {
  key_name = "terraform_book_aws"
}

########################################
# EC2 × 2台（SSM接続 & EFSマウント）
########################################

resource "aws_instance" "ssm" {
  count = 2

  ami                         = data.aws_ssm_parameter.al2023_default_x86_64.value
  instance_type               = "t3.micro"
  subnet_id                   = element(aws_subnet.private[*].id, count.index)
  vpc_security_group_ids      = [aws_security_group.ssm_instance.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ssm_profile.name
  key_name                    = data.aws_key_pair.this.key_name

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 15
    volume_type = "gp3"
    encrypted   = true
  }

  # ★ EFS マウント用 user_data（mount helper 使用）
  user_data = <<-EOF
              #!/bin/bash
              set -xe

              # amazon-efs-utils をインストール
              dnf -y install amazon-efs-utils || yum install -y amazon-efs-utils

              # マウントポイント作成
              mkdir -p /mnt/efs

              # EFS ファイルシステム ID（Terraform から埋め込み）
              FILE_SYSTEM_ID="${aws_efs_file_system.this.id}"

              # mount helper でマウント（TLS 有効）
              # 参考: https://docs.aws.amazon.com/ja_jp/efs/latest/ug/mounting-fs-mount-helper-ec2-linux.html
              mount -t efs -o tls $${FILE_SYSTEM_ID}:/ /mnt/efs

              # 再起動後もマウントされるよう /etc/fstab に追記
              echo "$${FILE_SYSTEM_ID}:/ /mnt/efs efs _netdev,tls 0 0" >> /etc/fstab

              # アプリ用ディレクトリを作って ec2-user に権限を付与
              TARGET_USER="ec2-user"
              mkdir -p /mnt/efs/shared
              chown $${TARGET_USER}:$${TARGET_USER} /mnt/efs/shared
              chmod 775 /mnt/efs/shared
              EOF

  tags = {
    Name = "${var.vpc_name}-ec2-ssm-${count.index}"
  }
}


# インスタンスIDを出力（2台分）
output "ssm_instance_ids" {
  description = "EC2 instance IDs for SSM-connected hosts"
  value       = aws_instance.ssm[*].id
}

# EFS のIDも一応出しておくと便利
output "efs_id" {
  description = "EFS file system ID"
  value       = aws_efs_file_system.this.id
}
