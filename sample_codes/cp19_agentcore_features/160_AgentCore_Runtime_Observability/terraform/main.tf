data "aws_caller_identity" "current" {}

locals {
  prefix   = "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  logs_arn = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "code" {
  bucket_prefix = "quote-observability-"
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
  source_hash = terraform_data.build.id
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
        Action   = ["dynamodb:GetItem"]
        Resource = aws_dynamodb_table.products.arn
      },
      {
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments"]
        Resource = "*"
      },
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
  description        = "Quote MCP with Gateway, Policy and internal OpenTelemetry spans"
  role_arn           = aws_iam_role.runtime.arn
  agent_runtime_artifact {
    code_configuration {
      runtime     = "PYTHON_3_14"
      entry_point = ["bootstrap.py"]
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
  environment_variables = {
    PRODUCT_TABLE                                      = aws_dynamodb_table.products.name
    AGENT_OBSERVABILITY_ENABLED                        = "true"
    OTEL_PYTHON_DISTRO                                 = "aws_distro"
    OTEL_PYTHON_CONFIGURATOR                           = "aws_configurator"
    OTEL_SERVICE_NAME                                  = "${local.gateway_name}-runtime"
    OTEL_TRACES_EXPORTER                               = "otlp"
    OTEL_EXPORTER_OTLP_PROTOCOL                        = "http/protobuf"
    OTEL_EXPORTER_OTLP_TRACES_ENDPOINT                 = "https://xray.${var.aws_region}.amazonaws.com/v1/traces"
    OTEL_METRICS_EXPORTER                              = "none"
    OTEL_LOGS_EXPORTER                                 = "none"
    OTEL_TRACES_SAMPLER                                = "parentbased_always_on"
    OTEL_PROPAGATORS                                   = "baggage,xray,tracecontext"
    OTEL_BSP_SCHEDULE_DELAY                            = "1000"
    OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT = "false"
    OTEL_PYTHON_DISABLED_INSTRUMENTATIONS              = "starlette,fastapi,httpx,requests,urllib3,logging,system_metrics"
    UNIFIED_TRACES_DESTINATION_ENABLED                 = "false"
  }
  protocol_configuration {
    server_protocol = "MCP"
  }
  # Omitting the JWT authorizer selects IAM (SigV4) authentication.
  lifecycle_configuration {
    idle_runtime_session_timeout = 60
    max_lifetime                 = 600
  }
  depends_on = [aws_iam_role_policy.runtime]
}
