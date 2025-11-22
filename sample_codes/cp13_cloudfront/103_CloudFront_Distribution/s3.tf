#---------------------------------------
# ランダムサフィックスでバケット名を一意化
#---------------------------------------
resource "random_id" "bucket" {
  byte_length = 4
}

locals {
  bucket_name = "${var.bucket_name_prefix}-${random_id.bucket.hex}"
}

resource "aws_s3_bucket" "site" {
  bucket = local.bucket_name
}