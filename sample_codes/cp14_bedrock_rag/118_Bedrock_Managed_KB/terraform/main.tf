locals {
  prefix      = "managed-kb-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  bedrock_arn = "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}"
  documents = toset([
    "meeting-01.txt",
    "meeting-01.txt.metadata.json",
    "meeting-02.txt",
    "meeting-02.txt.metadata.json",
    "meeting-03.txt",
    "meeting-03.txt.metadata.json",
  ])
}

resource "aws_bedrockagent_knowledge_base" "minutes" {
  name        = "managed-kb-relocation-minutes"
  description = "2023 MLIT relocation / dual residence committee minutes, meetings 1-3"
  role_arn    = aws_iam_role.knowledge_base.arn
  knowledge_base_configuration {
    type = "MANAGED"
    managed_knowledge_base_configuration { embedding_model_type = "MANAGED" }
  }
  depends_on = [aws_iam_role_policy.knowledge_base]
  lifecycle {
    precondition {
      condition = alltrue([
        for filename in local.documents : fileexists("${path.module}/../documents/${filename}")
      ])
      error_message = "The documents directory must contain meeting-01.txt through meeting-03.txt and their .metadata.json files."
    }
  }
}
resource "aws_bedrockagent_data_source" "minutes" {
  name                 = "committee-minutes"
  knowledge_base_id    = aws_bedrockagent_knowledge_base.minutes.id
  data_deletion_policy = "DELETE"
  data_source_configuration {
    type = "MANAGED_KNOWLEDGE_BASE_CONNECTOR"
    managed_knowledge_base_connector_configuration {
      deletion_protection_configuration {
        deletion_protection_status = "DISABLED"
      }
      media_extraction_configuration {
        image_extraction_configuration { image_extraction_status = "ENABLED" }
      }
      connector_parameters = jsonencode({
        aclEnabled          = false
        filterConfiguration = { maxFileSizeInMegaBytes = "500" }
        type                = "S3"
        version             = "1"
        connectionConfiguration = {
          bucketName           = aws_s3_bucket.documents.id
          bucketOwnerAccountId = data.aws_caller_identity.current.account_id
        }
      })
    }
  }
  vector_ingestion_configuration {
    parsing_configuration { parsing_strategy = "SMART_PARSING" }
  }
  depends_on = [aws_s3_object.documents]
}
