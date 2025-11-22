# --- VPCs ---
module "vpc_web" {
  source             = "../../../modules/vpc"
  vpc_cidr_block     = var.web_vpc_cidr_block
  vpc_name           = var.web_vpc_name
  availability_zones = var.availability_zones
  assign_ipv6        = var.enable_ipv6
}

module "vpc_vpn" {
  source             = "../../../modules/vpc"
  vpc_cidr_block     = var.vpn_vpc_cidr_block
  vpc_name           = var.vpn_vpc_name
  availability_zones = var.availability_zones
  assign_ipv6        = var.enable_ipv6
}

# --- VPC Peering (web <-> vpn) + DNS解決許可 ---
resource "aws_vpc_peering_connection" "web_to_vpn" {
  vpc_id      = module.vpc_web.vpc_id
  peer_vpc_id = module.vpc_vpn.vpc_id
  auto_accept = true
  tags        = { Name = "web-to-vpn-peering" }
}

resource "aws_vpc_peering_connection_options" "opts" {
  vpc_peering_connection_id = aws_vpc_peering_connection.web_to_vpn.id

  requester {
    allow_remote_vpc_dns_resolution = true
  }
  accepter {
    allow_remote_vpc_dns_resolution = true
  }
}

# 双方のプライベートRTに相互ルートを追加
resource "aws_route" "web_to_vpn_v4" {
  route_table_id            = module.vpc_web.private_route_table_id
  destination_cidr_block    = module.vpc_vpn.vpc_ipv4_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.web_to_vpn.id
}

resource "aws_route" "vpn_to_web_v4" {
  route_table_id            = module.vpc_vpn.private_route_table_id
  destination_cidr_block    = module.vpc_web.vpc_ipv4_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.web_to_vpn.id
}

resource "aws_route" "web_to_vpn_v6" {
  count                       = var.enable_ipv6 ? 1 : 0
  route_table_id              = module.vpc_web.private_route_table_id
  destination_ipv6_cidr_block = module.vpc_vpn.vpc_ipv6_cidr
  vpc_peering_connection_id   = aws_vpc_peering_connection.web_to_vpn.id
}

resource "aws_route" "vpn_to_web_v6" {
  count                       = var.enable_ipv6 ? 1 : 0
  route_table_id              = module.vpc_vpn.private_route_table_id
  destination_ipv6_cidr_block = module.vpc_web.vpc_ipv6_cidr
  vpc_peering_connection_id   = aws_vpc_peering_connection.web_to_vpn.id
}