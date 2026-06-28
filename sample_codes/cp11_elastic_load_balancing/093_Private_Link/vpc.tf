# ---- VPCの定義 ---- / VPC definitions
# VPC Aの定義 / Definition of VPC A
module "vpc_a" {
  source = "../../../modules/vpc"

  vpc_cidr_block     = var.vpc_a_cidr_block
  vpc_name           = var.vpc_a_name
  availability_zones = var.availability_zones
}

# VPC Bの定義 / Definition of VPC B
module "vpc_b" {
  source = "../../../modules/vpc"

  vpc_cidr_block     = var.vpc_b_cidr_block
  vpc_name           = var.vpc_b_name
  availability_zones = var.availability_zones
}
