terraform {
  backend "local" {
    path = ".cache/terraform.tfstate"
  }

  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.8.0"
    }
  }  
}

variable "aws_profile_name" {
  type    = string
  default = "develop"
}

provider "aws" {
  profile = var.aws_profile_name
}

resource "aws_vpc" "main" {
  cidr_block                       = var.vpc_cidr_block
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = true

  tags = {
    Name = var.vpc_name
  }
}

# Public subnet
resource "aws_subnet" "public" {
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = cidrsubnet(aws_vpc.main.cidr_block, 4, 0)
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 0)
  availability_zone               = "ap-northeast-1a"
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = true

  enable_resource_name_dns_a_record_on_launch    = true
  enable_resource_name_dns_aaaa_record_on_launch = true

  tags = {
    Name = "${var.vpc_name}-public-1"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

# カスタムルートテーブルを作成し、インターネットへのルートを追加
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # IPv4のデフォルトルート
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  # IPv6のデフォルトルート
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.vpc_name}-public-route-table"
  }
}

# 作成したルートテーブルをパブリックサブネットに関連付け
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

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

# 既存のキーペアを取得（存在しないと plan 時にエラー）
data "aws_key_pair" "this" {
  key_name = "terraform_book_aws"
}

# AMI を SSM パラメータストアから取得
data "aws_ssm_parameter" "al2023_default_x86_64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# EC2 インスタンス（パブリックサブネットに 1 台）
resource "aws_instance" "public_ec2" {
  ami                    = data.aws_ssm_parameter.al2023_default_x86_64.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ssh_only.id]
  key_name               = data.aws_key_pair.this.key_name

  # パブリックIPとIPv6を確実に付与
  associate_public_ip_address = true
  ipv6_address_count          = 1

  # ベストプラクティス（IMDSv2必須）
  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.vpc_name}-public-ec2-1"
  }
}

# 便利な出力（任意）
output "public_instance_public_ip" {
  value = aws_instance.public_ec2.public_ip
}

output "public_instance_public_dns" {
  value = aws_instance.public_ec2.public_dns
}

output "public_instance_ipv6" {
  value = try(aws_instance.public_ec2.ipv6_addresses[0], null)
}
