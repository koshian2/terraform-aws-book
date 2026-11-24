locals {
  prefix      = "${replace(var.name, "_", "-")}-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  bedrock_arn = "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  documents   = fileset("${path.module}/../documents", "**")
}

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
resource "aws_iam_role" "knowledge_base" {
  name_prefix = "${var.name}-kb-"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Action = "sts:AssumeRole", Principal = { Service = "bedrock.amazonaws.com" },
    Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }, ArnLike = { "aws:SourceArn" = "${local.bedrock_arn}:knowledge-base/*" } }
  }] })
}
resource "aws_iam_role_policy" "knowledge_base" {
  role = aws_iam_role.knowledge_base.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "s3:ListBucket", Resource = aws_s3_bucket.documents.arn },
    { Effect = "Allow", Action = "s3:GetObject", Resource = "${aws_s3_bucket.documents.arn}/documents/*" }
  ] })
}
# IAMの作成完了直後はBedrock側でAssumeRoleできない場合がある。
# ポリシーを変更した場合も、反映を待ってからKB・データソースを作成する。
resource "time_sleep" "knowledge_base_permissions" {
  create_duration = "60s"
  triggers = {
    role_arn = aws_iam_role.knowledge_base.arn
    trust    = sha256(aws_iam_role.knowledge_base.assume_role_policy)
    access   = sha256(aws_iam_role_policy.knowledge_base.policy)
  }
}

resource "aws_bedrockagent_knowledge_base" "shared" {
  name     = replace(var.name, "_", "-")
  role_arn = aws_iam_role.knowledge_base.arn
  knowledge_base_configuration {
    type = "MANAGED"
    managed_knowledge_base_configuration { embedding_model_type = "MANAGED" }
  }
  depends_on = [time_sleep.knowledge_base_permissions]
}
resource "aws_bedrockagent_data_source" "documents" {
  name                 = "tenant-documents"
  knowledge_base_id    = aws_bedrockagent_knowledge_base.shared.id
  data_deletion_policy = "DELETE"
  data_source_configuration {
    type = "MANAGED_KNOWLEDGE_BASE_CONNECTOR"
    managed_knowledge_base_connector_configuration {
      deletion_protection_configuration {
        deletion_protection_status    = "DISABLED"
        deletion_protection_threshold = 15
      }
      # AWSが補完する既定値を明示する。現行ProviderはJSONを文字列で比較するため、
      # GetDataSourceが返すキー順にも合わせる（動的な値はjsonencodeでエスケープ）。
      connector_parameters = join("", [
        "{\"type\":\"S3\",\"aclEnabled\":true,\"connectionConfiguration\":",
        jsonencode({ bucketName = aws_s3_bucket.documents.id, bucketOwnerAccountId = data.aws_caller_identity.current.account_id }),
        ",\"filterConfiguration\":{\"maxFileSizeInMegaBytes\":\"500\"},\"version\":\"1\"}"
      ])
      media_extraction_configuration {
        image_extraction_configuration {
          image_extraction_status = "ENABLED"
        }
      }
    }
  }
  vector_ingestion_configuration {
    parsing_configuration { parsing_strategy = "SMART_PARSING" }
  }
  depends_on = [aws_s3_object.documents, time_sleep.knowledge_base_permissions]
}
