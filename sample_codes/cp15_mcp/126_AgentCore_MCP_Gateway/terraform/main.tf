locals {
  artifact       = "${path.module}/../build/hello-world.zip"
  code_hash      = filesha256(local.artifact)
  arn_prefix     = "arn:${data.aws_partition.current.partition}"
  runtime_prefix = "${local.arn_prefix}:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  logs_prefix    = "${local.arn_prefix}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "code" {
  bucket_prefix = "agentcore-gateway-"
}

resource "aws_s3_bucket_public_access_block" "code" {
  bucket                  = aws_s3_bucket.code.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "code" {
  bucket = aws_s3_bucket.code.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_object" "code" {
  bucket      = aws_s3_bucket.code.id
  key         = "hello-world/${local.code_hash}.zip"
  source      = local.artifact
  source_hash = local.code_hash
  depends_on  = [aws_s3_bucket_public_access_block.code, aws_s3_bucket_server_side_encryption_configuration.code]
}

resource "aws_bedrockagentcore_agent_runtime" "hello" {
  agent_runtime_name = var.name
  description        = "MCP server returning Hello World"
  role_arn           = aws_iam_role.runtime.arn
  agent_runtime_artifact {
    code_configuration {
      runtime     = "PYTHON_3_14"
      entry_point = ["server.py"]
      code {
        s3 {
          bucket = aws_s3_bucket.code.id
          prefix = aws_s3_object.code.key
        }
      }
    }
  }
  network_configuration { network_mode = "PUBLIC" }
  protocol_configuration { server_protocol = "MCP" }
  lifecycle_configuration {
    idle_runtime_session_timeout = 60
    max_lifetime                 = 600
  }
  depends_on = [aws_iam_role_policy.runtime]
}
