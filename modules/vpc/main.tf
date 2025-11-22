resource "aws_vpc" "main" {
  cidr_block                       = var.vpc_cidr_block
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = var.assign_ipv6

  tags = merge(var.tags, {
    Name = var.vpc_name
  })
}

# Public subnets
resource "aws_subnet" "public" {
  count                           = length(var.availability_zones)
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = cidrsubnet(aws_vpc.main.cidr_block, 4, count.index)
  ipv6_cidr_block                 = var.assign_ipv6 ? cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, count.index) : null
  availability_zone               = element(var.availability_zones, count.index)
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = var.assign_ipv6

  enable_dns64                                   = false
  enable_resource_name_dns_a_record_on_launch    = true
  enable_resource_name_dns_aaaa_record_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-public-${count.index + 1}"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-igw"
  })
}

# Public route table (v4/v6 → IGW)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  dynamic "route" {
    for_each = var.assign_ipv6 ? [1] : []
    content {
      ipv6_cidr_block = "::/0"
      gateway_id      = aws_internet_gateway.igw.id
    }
  }

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-public-route-table"
  })
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private subnets
resource "aws_subnet" "private" {
  count                           = length(var.availability_zones)
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = cidrsubnet(aws_vpc.main.cidr_block, 4, length(var.availability_zones) + count.index)
  ipv6_cidr_block                 = var.assign_ipv6 ? cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, length(var.availability_zones) + count.index) : null
  availability_zone               = element(var.availability_zones, count.index)
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = var.assign_ipv6

  enable_dns64                                   = false
  enable_resource_name_dns_a_record_on_launch    = true
  enable_resource_name_dns_aaaa_record_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-private-${count.index + 1}"
  })
}

# Egress-Only IGW (IPv6外向き)
resource "aws_egress_only_internet_gateway" "eigw" {
  count  = var.assign_ipv6 ? 1 : 0
  vpc_id = aws_vpc.main.id
  tags = merge(var.tags, {
    Name = "${var.vpc_name}-eigw"
  })
}

# Private route table (IPv6はEIGW、IPv4はNATが有効な場合のみ後段で更新)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-private-route-table"
  })
}

resource "aws_route" "private_ipv6_default" {
  count                       = var.assign_ipv6 ? 1 : 0
  route_table_id              = aws_route_table.private.id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.eigw[0].id
}

# NAT (fck-nat) はオプション。IPv4の外向きが必要なときに有効化。
module "fck_nat" {
  source = "RaJiska/fck-nat/aws"
  # 0.13+ で module に count が利用可
  count   = var.enable_nat ? 1 : 0
  version = ">= 1.4.0, < 2.0.0"

  name      = "${var.vpc_name}-fck-nat"
  vpc_id    = aws_vpc.main.id
  subnet_id = aws_subnet.public[0].id

  ha_mode              = var.nat_ha_mode
  eip_allocation_ids   = var.nat_eip_allocation_ids
  use_cloudwatch_agent = var.nat_use_cloudwatch_agent

  instance_type = var.nat_instance_type
  ami_id        = var.nat_ami_id

  update_route_tables = true
  route_tables_ids = {
    "${var.vpc_name}-private-route-table" = aws_route_table.private.id
  }

  tags = var.tags
}

# Private subnets ↔ private route table
resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
