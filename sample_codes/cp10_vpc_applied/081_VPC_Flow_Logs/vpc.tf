module "vpc" {
  source = "../../../modules/vpc"

  vpc_cidr_block     = var.vpc_cidr_block
  vpc_name           = var.vpc_name
  availability_zones = var.availability_zones
}

#  VPC フローログの有効化
resource "aws_flow_log" "vpc" {
  vpc_id               = module.vpc.vpc_id
  log_destination_type = "s3"
  log_destination      = aws_s3_bucket.flow_logs.arn
  traffic_type         = "ALL"

  depends_on = [aws_s3_bucket_policy.flow_logs]
}