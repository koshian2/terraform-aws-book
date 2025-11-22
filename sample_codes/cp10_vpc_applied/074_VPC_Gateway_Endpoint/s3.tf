resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "aws_s3_bucket" "this" {
  bucket        = lower("${var.vpc_name}-bucket-${random_string.suffix.result}")
  force_destroy = true
  tags = {
    Name = "${var.vpc_name}-bucket"
  }
}

# バケット名を出力
output "s3_bucket_name" {
  value = aws_s3_bucket.this.id
}