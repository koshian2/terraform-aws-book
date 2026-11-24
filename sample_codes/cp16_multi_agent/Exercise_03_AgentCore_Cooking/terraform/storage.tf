resource "aws_s3_bucket" "documents" {
  bucket        = "${local.prefix}-documents"
  force_destroy = true
}
resource "aws_s3_bucket_public_access_block" "documents" {
  bucket                  = aws_s3_bucket.documents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3vectors_vector_bucket" "vectors" {
  vector_bucket_name = "${local.prefix}-vectors"
}
resource "aws_s3vectors_index" "documents" {
  vector_bucket_name = aws_s3vectors_vector_bucket.vectors.vector_bucket_name
  index_name         = "recipes"
  data_type          = "float32"
  dimension          = 1024
  distance_metric    = "cosine"
  metadata_configuration {
    non_filterable_metadata_keys = ["AMAZON_BEDROCK_TEXT", "AMAZON_BEDROCK_METADATA"]
  }
}
