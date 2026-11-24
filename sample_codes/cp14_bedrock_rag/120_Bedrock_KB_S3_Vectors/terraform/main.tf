locals {
  prefix        = "kb-s3vectors-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  bedrock_arn   = "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}"
  embedding_arn = "${local.bedrock_arn}::foundation-model/amazon.titan-embed-text-v2:0"
  documents     = toset(["meeting-01.txt", "meeting-01.txt.metadata.json", "meeting-02.txt", "meeting-02.txt.metadata.json", "meeting-03.txt", "meeting-03.txt.metadata.json"])
}

resource "aws_bedrockagent_knowledge_base" "minutes" {
  name        = "kb-s3vectors-relocation-minutes"
  description = "2023 MLIT relocation / dual residence committee minutes, meetings 1-3"
  role_arn    = aws_iam_role.knowledge_base.arn
  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = local.embedding_arn
      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions          = 1024
          embedding_data_type = "FLOAT32"
        }
      }
    }
  }
  storage_configuration {
    type = "S3_VECTORS"
    s3_vectors_configuration { index_arn = aws_s3vectors_index.documents.index_arn }
  }
  depends_on = [aws_iam_role_policy.knowledge_base]
  lifecycle {
    precondition {
      condition     = alltrue([for filename in local.documents : fileexists("${path.module}/../documents/${filename}")])
      error_message = "The documents directory must contain meeting-01.txt through meeting-03.txt and their .metadata.json files."
    }
  }
}
resource "aws_bedrockagent_data_source" "minutes" {
  name                 = "committee-minutes"
  knowledge_base_id    = aws_bedrockagent_knowledge_base.minutes.id
  data_deletion_policy = "DELETE"
  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = aws_s3_bucket.documents.arn
      inclusion_prefixes = ["documents/"]
    }
  }
  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = 500
        overlap_percentage = 15
      }
    }
  }
  depends_on = [aws_s3_object.documents]
}
