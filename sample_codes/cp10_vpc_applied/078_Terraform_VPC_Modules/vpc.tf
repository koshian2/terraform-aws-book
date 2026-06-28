module "vpc" {
  source = "../../../modules/vpc"

  vpc_cidr_block     = var.vpc_cidr_block
  vpc_name           = var.vpc_name
  availability_zones = var.availability_zones

  # IPv6を使う（EIGWによる外向きのみ） / Use IPv6 for outbound traffic through the egress-only internet gateway.
  assign_ipv6 = true
  # IPv4の外向きをNATで確保（不要ならfalse） / Use NAT for outbound IPv4. Set false if it is not needed.
  enable_nat = true

  tags = {
    Project = "terraform-book"
    Env     = "dev"
  }
}
