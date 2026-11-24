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
resource "aws_s3_object" "documents" {
  for_each     = local.documents
  bucket       = aws_s3_bucket.documents.id
  key          = "documents/${each.value}"
  source       = "${path.module}/../documents/${each.value}"
  source_hash  = filesha256("${path.module}/../documents/${each.value}")
  content_type = endswith(each.value, ".json") ? "application/json" : "text/plain; charset=utf-8"
  depends_on   = [aws_s3_bucket_public_access_block.documents, aws_s3_bucket_server_side_encryption_configuration.documents]
}
resource "aws_s3vectors_vector_bucket" "vectors" {
  vector_bucket_name = "${local.prefix}-vectors"
}
resource "aws_s3vectors_index" "documents" {
  vector_bucket_name = aws_s3vectors_vector_bucket.vectors.vector_bucket_name
  index_name         = "minutes"
  data_type          = "float32"
  dimension          = 1024
  distance_metric    = "cosine"
  metadata_configuration {
    non_filterable_metadata_keys = ["AMAZON_BEDROCK_TEXT", "AMAZON_BEDROCK_METADATA"]
  }
}
