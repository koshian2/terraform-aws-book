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

# インターネットゲートウェイ
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

# Public route table
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

# パブリック各サブネットに関連付け
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
  assign_ipv6_address_on_creation = true # Egress Only IGWに流しコストを節約する際に有効

  enable_dns64                                   = false
  enable_resource_name_dns_a_record_on_launch    = true
  enable_resource_name_dns_aaaa_record_on_launch = true

  tags = {
    Name = "${var.vpc_name}-private-${count.index + 1}"
  }
}

# Egress-Only インターネットゲートウェイ
resource "aws_egress_only_internet_gateway" "eigw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.vpc_name}-eigw"
  }
}

# プライベートルートテーブル
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # IPv6 デフォルトは EIGW（外向きのみ）
  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.eigw.id
  }

  tags = {
    Name = "${var.vpc_name}-private-route-table"
  }
}

# プライベート各サブネットに関連付け
resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# VPCエンドポイント用セキュリティグループ（VPC内→443のみ）
resource "aws_security_group" "vpce" {
  name                   = "${var.vpc_name}-vpce-sg"
  description            = "Allow HTTPS from VPC to Interface Endpoints"
  vpc_id                 = aws_vpc.main.id
  revoke_rules_on_delete = true

  tags = { Name = "${var.vpc_name}-vpce-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "vpce_https_v4" {
  security_group_id = aws_security_group.vpce.id
  description       = "HTTPS from VPC IPv4"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = aws_vpc.main.cidr_block
}

resource "aws_vpc_security_group_ingress_rule" "vpce_https_v6" {
  security_group_id = aws_security_group.vpce.id
  description       = "HTTPS from VPC IPv6"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv6         = aws_vpc.main.ipv6_cidr_block
}

resource "aws_vpc_security_group_egress_rule" "vpce_all_v4" {
  security_group_id = aws_security_group.vpce.id
  description       = "All egress IPv4"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "vpce_all_v6" {
  security_group_id = aws_security_group.vpce.id
  description       = "All egress IPv6"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}

locals {
  # 作成するエンドポイントのサービス名をリスト化
  session_manager_services = toset([
    "ssm",
    "ssmmessages",
    "ec2messages"
  ])
}

# データソースでサービス名を取得
data "aws_vpc_endpoint_service" "session_manager" {
  for_each = local.session_manager_services
  service  = each.key
}

# Interface VPC Endpoints（Private DNS 有効）
resource "aws_vpc_endpoint" "session_manager" {
  for_each = local.session_manager_services

  vpc_id            = aws_vpc.main.id
  service_name      = data.aws_vpc_endpoint_service.session_manager[each.key].service_name
  vpc_endpoint_type = "Interface"
  # 可用性を考慮する場合は aws_subnet.private[*].id とする
  # ただし、エンドポイントが配置される「サブネットの数×3（この例では9）」時間料金が発生するためコストに注意
  subnet_ids          = [aws_subnet.private[0].id]
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce.id]

  tags = { Name = "${var.vpc_name}-vpce-${each.key}" }
}