# ---- VPCの定義 ----
# VPC Aの定義
module "vpc_a" {
  source = "../../../modules/vpc"

  vpc_cidr_block     = var.vpc_a_cidr_block
  vpc_name           = var.vpc_a_name
  availability_zones = var.availability_zones
}

# VPC Bの定義
module "vpc_b" {
  source = "../../../modules/vpc"

  vpc_cidr_block     = var.vpc_b_cidr_block
  vpc_name           = var.vpc_b_name
  availability_zones = var.availability_zones
}

# ---- VPC Peering ----
resource "aws_vpc_peering_connection" "a_to_b" {
  vpc_id      = module.vpc_a.vpc_id
  peer_vpc_id = module.vpc_b.vpc_id
  auto_accept = true # 同一アカウント/リージョンなら自動承諾

  tags = {
    Name = "${var.vpc_a_name}<->${var.vpc_b_name}"
  }
}

# オプション：DNS 解決を相互許可（Route 53 Private Hosted Zone 越しの名前解決などで有用）
# この例でも、相手方のVPCにあるEC2のプライベートリソースDNSの名前解決が可能になる
resource "aws_vpc_peering_connection_options" "a_to_b" {
  vpc_peering_connection_id = aws_vpc_peering_connection.a_to_b.id

  requester {
    allow_remote_vpc_dns_resolution = true
  }
  accepter {
    allow_remote_vpc_dns_resolution = true
  }
}

# ---- ルートテーブルの更新 ----
locals {
  a_route_tables = {
    public  = module.vpc_a.public_route_table_id
    private = module.vpc_a.private_route_table_id
  }
  b_route_tables = {
    public  = module.vpc_b.public_route_table_id
    private = module.vpc_b.private_route_table_id
  }
}

# A -> B (両方の RT に同じ宛先ルートを作成)
resource "aws_route" "a_to_b" {
  for_each                  = local.a_route_tables
  route_table_id            = each.value
  destination_cidr_block    = module.vpc_b.vpc_ipv4_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.a_to_b.id
}

# B -> A
resource "aws_route" "b_to_a" {
  for_each                  = local.b_route_tables
  route_table_id            = each.value
  destination_cidr_block    = module.vpc_a.vpc_ipv4_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.a_to_b.id
}
