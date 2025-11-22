# EC2用 セキュリティグループ（EICからのSSHを許可）
resource "aws_security_group" "ec2_from_eic" {
  name        = "${var.vpc_name}-ec2-from-eic-sg"
  description = "Allow SSH from EC2 Instance Connect Endpoint"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-ec2-from-eic-sg"
  }
}

# EC2 <- EICエンドポイント (SSH/22) を許可（EC2側の受信許可）
resource "aws_vpc_security_group_ingress_rule" "ec2_allow_ssh_from_eic" {
  security_group_id            = aws_security_group.ec2_from_eic.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.eic.id
}

resource "aws_vpc_security_group_egress_rule" "ec2_allow_all_ipv4" {
  security_group_id = aws_security_group.ec2_from_eic.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "All IPv4 egress"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  security_group_id = aws_security_group.ec2_from_eic.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
  description       = "All IPv6 egress (via Egress-only IGW)"
}

# AMI（Amazon Linux 2023, x86_64）
data "aws_ssm_parameter" "al2023_default_x86_64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

#  EC2（各プライベートサブネットに1台ずつ）
resource "aws_instance" "private" {
  count                       = length(aws_subnet.private)
  ami                         = data.aws_ssm_parameter.al2023_default_x86_64.value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private[count.index].id
  vpc_security_group_ids      = [aws_security_group.ec2_from_eic.id] # EICからの22/tcpを受けるSGを必ずアタッチ
  associate_public_ip_address = false

  metadata_options {
    http_tokens = "required"
  }

  # 必要ならキーペアを使う（EICの一時鍵運用だけなら不要）
  # key_name = "your-keypair-name"

  tags = {
    Name = "${var.vpc_name}-private-ec2-${count.index + 1}"
  }
}

# 参考出力
output "private_instance_ids" {
  value = [for i in aws_instance.private : i.id]
}

output "private_instance_private_ips" {
  value = [for i in aws_instance.private : i.private_ip]
}
