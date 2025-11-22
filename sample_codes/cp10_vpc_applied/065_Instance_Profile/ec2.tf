# セキュリティグループ本体
resource "aws_security_group" "ssh_only" {
  name        = "${var.vpc_name}-ssh"
  description = "Allow SSH only from my IP; allow all IPv4 and IPv6 egress"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-ssh-sg"
  }

  # （任意）削除時にルールを全削除したい場合
  revoke_rules_on_delete = true
}

# Ingress: 自分のIPv4からのみSSH(22/tcp)
resource "aws_vpc_security_group_ingress_rule" "ssh_from_my_ipv4" {
  security_group_id = aws_security_group.ssh_only.id
  description       = "SSH from my IPv4"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = "${var.my_ip}/32"
}

# Egress: IPv4 全許可
resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.ssh_only.id
  description       = "Allow all IPv4 egress"
  ip_protocol       = "-1" # all protocols / all ports
  cidr_ipv4         = "0.0.0.0/0"
}

# Egress: IPv6 全許可
resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  security_group_id = aws_security_group.ssh_only.id
  description       = "Allow all IPv6 egress"
  ip_protocol       = "-1" # all protocols / all ports
  cidr_ipv6         = "::/0"
}

# 既存のキーペアを取得
data "aws_key_pair" "this" {
  key_name = "terraform_book_aws"
}

# AMI を SSM パラメータストアから取得
data "aws_ssm_parameter" "al2023_default_x86_64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# EC2 用 IAM ロール
resource "aws_iam_role" "ec2_s3_readonly_role" {
  name = "ec2-s3-readonly-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# S3 ReadOnly のマネージドポリシーをアタッチ
resource "aws_iam_role_policy_attachment" "ec2_s3_readonly_attach" {
  role       = aws_iam_role.ec2_s3_readonly_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# インスタンスプロファイル
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-s3-readonly-profile"
  role = aws_iam_role.ec2_s3_readonly_role.name
}

# EC2 インスタンス（パブリックサブネットに 1 台）
resource "aws_instance" "public_ec2" {
  ami                    = data.aws_ssm_parameter.al2023_default_x86_64.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ssh_only.id]
  key_name               = data.aws_key_pair.this.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name # ここを追加

  associate_public_ip_address = true
  ipv6_address_count          = 1

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.vpc_name}-public-ec2-1"
  }
}

# DNS名を出力
output "public_instance_public_dns" {
  value = aws_instance.public_ec2.public_dns
}
