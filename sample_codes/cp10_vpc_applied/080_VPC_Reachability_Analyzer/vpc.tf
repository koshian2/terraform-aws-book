# ---- VPCの定義 ----
module "vpc" {
  source = "../../../modules/vpc"

  vpc_cidr_block     = var.vpc_cidr_block
  vpc_name           = var.vpc_name
  availability_zones = var.availability_zones
}
