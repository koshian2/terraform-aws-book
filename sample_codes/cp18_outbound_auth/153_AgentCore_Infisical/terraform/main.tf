data "aws_caller_identity" "current" {}

locals {
  prefix   = "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  logs_arn = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "code" {
  bucket_prefix = "agentcore-demo-"
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
  bucket = aws_s3_bucket.code.id
  key    = "demo/${local.build_hash}.zip"
  source = local.artifact
  # A new build ID also forces upload when explicitly rebuilding a missing ZIP.
  source_hash = local.build_hash
  depends_on  = [aws_s3_bucket_public_access_block.code, aws_s3_bucket_server_side_encryption_configuration.code]
}

resource "aws_iam_role" "runtime" {
  name = "${var.name}_runtime"
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
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.code.arn}/demo/*"
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
  description        = "Read a demo configuration using Infisical AWS Auth"
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
  environment_variables = {
    INFISICAL_HOST        = var.infisical_host
    INFISICAL_IDENTITY_ID = infisical_identity.runtime.id
    INFISICAL_PROJECT_ID  = infisical_project.demo.id
    STS_REGION            = var.aws_region
  }
  # Omitting the JWT authorizer selects IAM (SigV4) authentication.
  lifecycle_configuration {
    idle_runtime_session_timeout = 60
    max_lifetime                 = 600
  }
  depends_on = [aws_iam_role_policy.runtime, infisical_identity_aws_auth.runtime, infisical_project_identity.runtime, infisical_secret.message]
}
