# 既存のキーペアを取得 / Get the existing key pair
data "aws_key_pair" "this" {
  key_name = "terraform_book_aws"
}

# AMI を SSM パラメータストアから取得 / Get the AMI from SSM Parameter Store
data "aws_ssm_parameter" "al2023_default_x86_64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# セキュリティグループ本体 / Security group resource
resource "aws_security_group" "ssh_http_only" {
  name        = "${var.vpc_name}-ssh"
  description = "Allow SSH from my IP and HTTP(80) from anywhere; allow all IPv4 and IPv6 egress"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-ssh-sg"
  }

  # （任意）削除時にルールを全削除したい場合 / Optional: delete all rules when the security group is removed
  revoke_rules_on_delete = true
}

# Ingress: HTTP(80/tcp) を全IPv4から許可 / Ingress: allow HTTP (80/tcp) from all IPv4 addresses
resource "aws_vpc_security_group_ingress_rule" "http_ipv4" {
  security_group_id = aws_security_group.ssh_http_only.id
  description       = "HTTP from anywhere (IPv4)"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# Ingress: HTTP(80/tcp) を全IPv6から許可 / Ingress: allow HTTP (80/tcp) from all IPv6 addresses
resource "aws_vpc_security_group_ingress_rule" "http_ipv6" {
  security_group_id = aws_security_group.ssh_http_only.id
  description       = "HTTP from anywhere (IPv6)"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv6         = "::/0"
}

# Ingress: 自分のIPv4からのみSSH(22/tcp) / Ingress: allow SSH (22/tcp) only from your IPv4 address
resource "aws_vpc_security_group_ingress_rule" "ssh_from_my_ipv4" {
  security_group_id = aws_security_group.ssh_http_only.id
  description       = "SSH from my IPv4"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = "${var.my_ip}/32"
}

# Egress: IPv4 全許可 / Egress: allow all IPv4 traffic
resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.ssh_http_only.id
  description       = "Allow all IPv4 egress"
  ip_protocol       = "-1" # all protocols / all ports
  cidr_ipv4         = "0.0.0.0/0"
}

# Egress: IPv6 全許可 / Egress: allow all IPv6 traffic
resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  security_group_id = aws_security_group.ssh_http_only.id
  description       = "Allow all IPv6 egress"
  ip_protocol       = "-1" # all protocols / all ports
  cidr_ipv6         = "::/0"
}

# EC2 インスタンス（パブリックサブネットに 1 台） / One EC2 instance in the public subnet
resource "aws_instance" "public_ec2" {
  ami                    = data.aws_ssm_parameter.al2023_default_x86_64.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ssh_http_only.id]
  key_name               = data.aws_key_pair.this.key_name

  associate_public_ip_address = false # ここをfalseに / Set this to false.
  ipv6_address_count          = 1

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y httpd
    systemctl start httpd
    systemctl enable httpd
  EOF

  # user_data を変えたら置き換え / Replace the instance when user_data changes.
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.vpc_name}-public-ec2-1"
  }
}

# Elastic IP を取得 / Get an Elastic IP.
resource "aws_eip" "public_ec2" {
  domain = "vpc"
  tags = {
    Name = "${var.vpc_name}-public-ec2-eip"
  }
}

# EC2 に EIP をアタッチ / Attach an EIP to EC2.
resource "aws_eip_association" "public_ec2" {
  allocation_id = aws_eip.public_ec2.id
  instance_id   = aws_instance.public_ec2.id
}

# 出力（EIP の固定 IPv4） / Output the fixed IPv4 address of the EIP.
output "public_instance_eip" {
  value = aws_eip.public_ec2.public_ip
}
