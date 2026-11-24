locals {
  prefix      = "managed-kb-pdf-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  bedrock_arn = "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}"
  documents   = toset(["relocation-direction.pdf", "relocation-direction.pdf.metadata.json"])
}

resource "aws_bedrockagent_knowledge_base" "minutes" {
  name        = "managed-kb-pdf-relocation-pdf"
  description = "MLIT committee slide deck: all 10 PDF pages, charts and diagrams"
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
      error_message = "The documents directory must contain relocation-direction.pdf and its .metadata.json file. See commands.sh for the download command."
    }
  }
}
resource "aws_bedrockagent_data_source" "minutes" {
  name                 = "committee-pdf"
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
