module "vpc" {
  source = "../../../modules/vpc"

  vpc_cidr_block     = var.vpc_cidr_block
  vpc_name           = var.vpc_name
  availability_zones = var.availability_zones

  # IPv6を使う（EIGWによる外向きのみ）
  assign_ipv6 = true
  # IPv4の外向きをNATで確保（不要ならfalse）
  enable_nat = true

  tags = {
    Project = "terraform-book"
    Env     = "dev"
  }
}
