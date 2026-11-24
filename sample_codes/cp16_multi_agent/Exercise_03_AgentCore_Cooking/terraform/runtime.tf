variable "actor_id" {
  type    = string
  default = "demo-cook"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$", var.actor_id))
    error_message = "actor_id must contain 1-80 letters, digits, underscores or hyphens."
  }
}
data "aws_bedrock_inference_profile" "model" { inference_profile_id = var.model_id }
locals {
  runtime_name  = "cooking_assistant"
  agentcore_arn = "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  logs_arn      = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  build_hash    = sha256(jsonencode({ for f in ["app/runtime.py", "app/agent.py", "app/memory.py", "scripts/build.py", "pyproject.toml", "uv.lock"] : f => filesha256("${path.module}/../${f}") }))
}
resource "aws_bedrockagentcore_memory" "conversation" {
  name                  = "cooking_conversations"
  event_expiry_duration = 7
}
resource "terraform_data" "build" {
  triggers_replace = local.build_hash
  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = "uv run --frozen python scripts/build.py"
  }
}
resource "aws_s3_bucket" "code" {
  bucket_prefix = "cooking-code-"
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
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_object" "code" {
  bucket      = aws_s3_bucket.code.id
  key         = "runtime/${local.build_hash}.zip"
  source      = "${path.module}/../build/runtime.zip"
  source_hash = terraform_data.build.id
  depends_on  = [aws_s3_bucket_public_access_block.code, aws_s3_bucket_server_side_encryption_configuration.code]
}
resource "aws_iam_role" "runtime" {
  name = "cooking-runtime-${var.aws_region}"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "bedrock-agentcore.amazonaws.com" },
    Condition = {
      StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      ArnLike      = { "aws:SourceArn" = "${local.agentcore_arn}:*" }
    }
  }] })
}
resource "aws_iam_role_policy" "runtime" {
  role = aws_iam_role.runtime.id
  name = "cooking-memory-search-model"
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "s3:GetObject", Resource = "${aws_s3_bucket.code.arn}/runtime/*" },
    { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:DescribeLogStreams", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${local.logs_arn}:log-group:/aws/bedrock-agentcore/runtimes/${local.runtime_name}-*" },
    { Effect = "Allow", Action = "logs:DescribeLogGroups", Resource = "${local.logs_arn}:log-group:*" },
    { Effect = "Allow", Action = ["bedrock-agentcore:CreateEvent", "bedrock-agentcore:ListEvents", "bedrock-agentcore:ListSessions"], Resource = aws_bedrockagentcore_memory.conversation.arn },
    { Effect = "Allow", Action = "bedrock:Retrieve", Resource = aws_bedrockagent_knowledge_base.recipes.arn },
    { Effect = "Allow", Action = "bedrock:InvokeModel", Resource = concat([data.aws_bedrock_inference_profile.model.inference_profile_arn], [for m in data.aws_bedrock_inference_profile.model.models : m.model_arn]) }
  ] })
}
resource "aws_bedrockagentcore_agent_runtime" "cooking" {
  agent_runtime_name = local.runtime_name
  role_arn           = aws_iam_role.runtime.arn
  environment_variables = {
    SAMPLE_REGION     = var.aws_region, MODEL_ID = var.model_id, ACTOR_ID = var.actor_id
    MEMORY_ID         = aws_bedrockagentcore_memory.conversation.id
    KNOWLEDGE_BASE_ID = aws_bedrockagent_knowledge_base.recipes.id
  }
  agent_runtime_artifact {
    code_configuration {
      runtime     = "PYTHON_3_14"
      entry_point = ["runtime.py"]
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
    max_lifetime                 = 900
  }
  depends_on = [aws_iam_role_policy.runtime]
}
