
locals {
  artifact  = "${path.module}/../build/runtime.zip"
  code_hash = filesha256(local.artifact)
  prefix    = "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  logs_arn  = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "code" {
  bucket_prefix = "${replace(var.name, "_", "-")}-"
  force_destroy = true
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
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "code" {
  bucket      = aws_s3_bucket.code.id
  key         = "runtime/${local.code_hash}.zip"
  source      = local.artifact
  source_hash = local.code_hash
  depends_on  = [aws_s3_bucket_public_access_block.code, aws_s3_bucket_server_side_encryption_configuration.code]
}

resource "aws_iam_role" "runtime" {
  name_prefix = "${var.name}-runtime-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "bedrock-agentcore.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "${local.prefix}:*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "runtime" {
  name = "demo_runtime"
  role = aws_iam_role.runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sts:AssumeRole", "sts:TagSession"], Resource = aws_iam_role.reader.arn, Condition = local.session_conditions },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.code.arn}/runtime/*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:DescribeLogStreams", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${local.logs_arn}:log-group:/aws/bedrock-agentcore/runtimes/${var.name}-*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "${local.logs_arn}:log-group:*"
      }
    ]
  })
}

resource "aws_bedrockagentcore_agent_runtime" "demo" {
  agent_runtime_name = var.name
  description        = "Shared DynamoDB table isolated by LeadingKeys and tenant session tags"
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
  network_configuration {
    network_mode = "PUBLIC"
  }
  protocol_configuration {
    server_protocol = "MCP"
  }
  request_header_configuration {
    request_header_allowlist = [local.tenant_header]
  }
  environment_variables = {
    ALLOWED_TENANTS = jsonencode(keys(local.tenants))
    TABLE_NAME      = aws_dynamodb_table.inquiries.name
    DATA_REGION     = var.aws_region
    READER_ROLE_ARN = aws_iam_role.reader.arn
  }
  # Omitting the JWT authorizer selects IAM (SigV4) authentication.
  lifecycle_configuration {
    idle_runtime_session_timeout = 60
    max_lifetime                 = 600
  }
  depends_on = [aws_iam_role_policy.runtime, aws_iam_role_policy.reader, aws_dynamodb_table_item.demo]
}
