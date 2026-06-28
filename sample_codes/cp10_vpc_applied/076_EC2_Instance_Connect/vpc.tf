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
  count                           = length(var.availability_zones)
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = cidrsubnet(aws_vpc.main.cidr_block, 4, count.index)
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, count.index)
  availability_zone               = element(var.availability_zones, count.index)
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = true

  enable_dns64                                   = false
  enable_resource_name_dns_a_record_on_launch    = true
  enable_resource_name_dns_aaaa_record_on_launch = true

  tags = {
    Name = "${var.vpc_name}-public-${count.index + 1}"
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
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private subnet
resource "aws_subnet" "private" {
  count                           = length(var.availability_zones)
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = cidrsubnet(aws_vpc.main.cidr_block, 4, length(var.availability_zones) + count.index)
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, length(var.availability_zones) + count.index)
  availability_zone               = element(var.availability_zones, count.index)
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = true # Egress Only IGWに流しコストを節約する際に有効 / Enable this when sending IPv6 traffic through the egress-only internet gateway to save cost.

  enable_dns64                                   = false
  enable_resource_name_dns_a_record_on_launch    = true
  enable_resource_name_dns_aaaa_record_on_launch = true

  tags = {
    Name = "${var.vpc_name}-private-${count.index + 1}"
  }
}

# Egress-Only インターネットゲートウェイ / Egress-only internet gateway
resource "aws_egress_only_internet_gateway" "eigw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.vpc_name}-eigw"
  }
}

# プライベートルートテーブル / Private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.eigw.id
  }

  tags = {
    Name = "${var.vpc_name}-private-route-table"
  }
}

# プライベート各サブネットに関連付け / Associate with each private subnet
resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# EIC用 セキュリティグループ（エンドポイント側） / Security group for EIC on the endpoint side
resource "aws_security_group" "eic" {
  name        = "${var.vpc_name}-eic-sg"
  description = "Security group for EC2 Instance Connect Endpoint"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-eic-sg"
  }
}

# EICエンドポイント -> EC2 (SSH/22) を許可（エンドポイントの送信許可） / Allow EIC endpoint to EC2 on SSH/22 as endpoint egress
resource "aws_vpc_security_group_egress_rule" "eic_to_ec2_ssh" {
  security_group_id            = aws_security_group.eic.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.ec2_from_eic.id
}

# 1つ目のプライベートサブネットに EIC エンドポイントを作成 / Create the EIC endpoint in the first private subnet.
resource "aws_ec2_instance_connect_endpoint" "this" {
  subnet_id          = aws_subnet.private[0].id
  security_group_ids = [aws_security_group.eic.id]

  # クライアントIPは保持しない（EICのSGをソースとしてEC2側で許可） / Do not preserve the client IP. Allow access on the EC2 side by using the EIC security group as the source.
  preserve_client_ip = false

  tags = {
    Name = "${var.vpc_name}-eice"
  }
}

# 参考: 出力 / Reference outputs.
output "eic_endpoint_id" {
  value = aws_ec2_instance_connect_endpoint.this.id
}
