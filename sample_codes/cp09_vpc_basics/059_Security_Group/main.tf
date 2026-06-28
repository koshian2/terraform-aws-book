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

variable "vpc_cidr_block" {
  description = "VPCのCIDRブロック / VPC CIDR block"
  type        = string
  default     = "10.32.0.0/16"
}

variable "vpc_name" {
  description = "VPCの名前 / VPC name"
  type        = string
  default     = "terraform-book-vpc"
}

variable "my_ip" {
  description = "あなたのグローバルIPv4（CIDRなし、例: 203.0.113.10） / Your global IPv4 address without CIDR, for example 203.0.113.10"
  type        = string
  default     = "203.0.113.10" # ここを自分のIPに置き換える / Replace this with your own IP address

  # 入力チェック（有効なIPv4かを /32 を付けて検証） / Input check: add /32 and verify that it is a valid IPv4 address
  validation {
    condition     = can(cidrhost("${var.my_ip}/32", 0))
    error_message = "有効なIPv4アドレスを指定してください（例: 203.0.113.10）。 / Enter a valid IPv4 address, for example 203.0.113.10."
  }
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

# カスタムルートテーブルを作成し、インターネットへのルートを追加 / Create a custom route table and add routes to the internet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # IPv4のデフォルトルート / IPv4 default route
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  # IPv6のデフォルトルート / IPv6 default route
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.vpc_name}-public-route-table"
  }
}

# 作成したルートテーブルをパブリックサブネットに関連付け / Associate the created route table with the public subnet
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# セキュリティグループ本体 / Security group resource
resource "aws_security_group" "ssh_only" {
  name        = "${var.vpc_name}-ssh"
  description = "Allow SSH only from my IP; allow all IPv4 egress"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-ssh-sg"
  }
}

# Ingress: 自分のIPv4からのみSSH(22/tcp) / Ingress: allow SSH (22/tcp) only from your IPv4 address
resource "aws_vpc_security_group_ingress_rule" "ssh_from_my_ipv4" {
  security_group_id = aws_security_group.ssh_only.id
  description       = "SSH from my IPv4"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = "${var.my_ip}/32"
}

# Egress: IPv4 全許可 / Egress: allow all IPv4 traffic
resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.ssh_only.id
  description       = "Allow all IPv4 egress"
  ip_protocol       = "-1" # all protocols / all ports
  cidr_ipv4         = "0.0.0.0/0"
}
