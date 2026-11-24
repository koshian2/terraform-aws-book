data "aws_caller_identity" "current" {}
locals {
  prefix   = "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  logs_arn = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
}
resource "aws_s3_bucket" "code" { bucket_prefix = "stationery-evaluation-" }
resource "aws_s3_bucket_public_access_block" "code" {
  bucket                  = aws_s3_bucket.code.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_object" "code" {
  bucket      = aws_s3_bucket.code.id
  key         = "demo/${local.build_hash}.zip"
  source      = local.artifact
  source_hash = terraform_data.build.id
  depends_on  = [aws_s3_bucket_public_access_block.code]
}
resource "aws_iam_role" "runtime" {
  name = "${var.name}_runtime"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Action = "sts:AssumeRole", Principal = { Service = "bedrock-agentcore.amazonaws.com" },
    Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }, ArnLike = { "aws:SourceArn" = "${local.prefix}:*" } }
  }] })
}
resource "aws_iam_role_policy" "runtime" {
  role = aws_iam_role.runtime.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.code.arn}/demo/*" },
    { Effect = "Allow", Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"], Resource = [
      "arn:aws:bedrock:*::foundation-model/anthropic.claude-*",
      "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.model_id}"
    ] },
    { Effect = "Allow", Action = ["xray:PutTraceSegments"], Resource = "*" },
    { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"], Resource = "${local.logs_arn}:log-group:/aws/bedrock-agentcore/runtimes/${var.name}-*" },
    { Effect = "Allow", Action = ["logs:DescribeLogGroups"], Resource = "*" }
  ] })
}
resource "aws_bedrockagentcore_agent_runtime" "demo" {
  agent_runtime_name = var.name
  description        = "Stationery assistant with continuous quality evaluation"
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
  network_configuration { network_mode = "PUBLIC" }
  protocol_configuration { server_protocol = "HTTP" }
  lifecycle_configuration {
    idle_runtime_session_timeout = 300
    max_lifetime                 = 900
  }
  environment_variables = {
    MODEL_ID                                           = var.model_id
    AGENT_OBSERVABILITY_ENABLED                        = "true"
    OTEL_PYTHON_DISTRO                                 = "aws_distro"
    OTEL_PYTHON_CONFIGURATOR                           = "aws_configurator"
    OTEL_SERVICE_NAME                                  = "${var.name}.DEFAULT"
    OTEL_TRACES_EXPORTER                               = "otlp"
    OTEL_EXPORTER_OTLP_PROTOCOL                        = "http/protobuf"
    OTEL_EXPORTER_OTLP_TRACES_ENDPOINT                 = "https://xray.${var.aws_region}.amazonaws.com/v1/traces"
    OTEL_METRICS_EXPORTER                              = "none"
    OTEL_LOGS_EXPORTER                                 = "none"
    OTEL_TRACES_SAMPLER                                = "always_on"
    OTEL_PROPAGATORS                                   = "baggage,xray,tracecontext"
    OTEL_BSP_SCHEDULE_DELAY                            = "1000"
    OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT = "true"
    AWS_GENAI_CONTENT_EXTRACTION_OPT_OUT               = "true"
    UNIFIED_TRACES_DESTINATION_ENABLED                 = "true"
  }
  depends_on = [aws_iam_role_policy.runtime]
}

locals {
  runtime_log = "/aws/bedrock-agentcore/runtimes/${aws_bedrockagentcore_agent_runtime.demo.agent_runtime_id}-DEFAULT"
}
resource "terraform_data" "logs" {
  triggers_replace = aws_bedrockagentcore_agent_runtime.demo.agent_runtime_id
  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = "uv run --frozen python scripts/logs.py"
    environment = {
      DEMO_LOG_GROUP     = local.runtime_log
      AWS_PROFILE        = var.aws_profile
      AWS_DEFAULT_REGION = var.aws_region
    }
  }
}
