terraform {
  required_version = ">= 1.12, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "= 6.66.0" }
  }
  backend "local" { path = "terraform.tfstate" }
}
variable "aws_profile" {
  type    = string
  default = "develop"
}
variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}
variable "model_id" {
  type    = string
  default = "jp.anthropic.claude-sonnet-4-6"
}
provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
  default_tags { tags = { Project = "groupchat", ManagedBy = "Terraform" } }
}
data "aws_caller_identity" "current" {}
data "aws_bedrock_inference_profile" "model" { inference_profile_id = var.model_id }
locals {
  stages     = toset(["development", "procurement", "operations", "summary"])
  roles      = toset(["development", "procurement", "operations", "summary", "pipeline"])
  prefix     = "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  logs       = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  build_hash = sha256(jsonencode({ for f in ["app/worker.py", "app/pipeline.py", "app/contracts.py", "app/calculator.py", "app/memory.py", "scripts/build.py", "pyproject.toml", "uv.lock"] : f => filesha256("${path.module}/../${f}") }))
  assume = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "bedrock-agentcore.amazonaws.com" },
    Condition = {
      StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      ArnLike      = { "aws:SourceArn" = "${local.prefix}:*" }
    }
  }] })
}
resource "terraform_data" "build" {
  triggers_replace = local.build_hash
  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = "uv run --frozen python scripts/build.py"
  }
}
resource "aws_s3_bucket" "code" { bucket_prefix = "groupchat-code-" }
resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "groupchat-reports-"
  # This dedicated sample bucket contains sample data and generated reports only. Destroy deletes them too.
  force_destroy = true
}
resource "aws_s3_bucket_public_access_block" "buckets" {
  for_each                = { code = aws_s3_bucket.code.id, artifacts = aws_s3_bucket.artifacts.id }
  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "buckets" {
  for_each = { code = aws_s3_bucket.code.id, artifacts = aws_s3_bucket.artifacts.id }
  bucket   = each.value
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_object" "code" {
  for_each    = toset(["worker", "pipeline"])
  bucket      = aws_s3_bucket.code.id
  key         = "${each.key}/${local.build_hash}.zip"
  source      = "${path.module}/../build/${each.key}.zip"
  source_hash = terraform_data.build.id
  depends_on  = [aws_s3_bucket_public_access_block.buckets, aws_s3_bucket_server_side_encryption_configuration.buckets]
}
resource "aws_iam_role" "runtime" {
  for_each           = local.roles
  name               = "groupchat_${each.key}"
  assume_role_policy = local.assume
}
resource "aws_iam_role_policy" "base" {
  for_each = local.roles
  role     = aws_iam_role.runtime[each.key].id
  name     = "code_and_logs"
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "s3:GetObject", Resource = "${aws_s3_bucket.code.arn}/${each.key == "pipeline" ? "pipeline" : "worker"}/*" },
    { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:DescribeLogStreams", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${local.logs}:log-group:/aws/bedrock-agentcore/runtimes/groupchat_${each.key}-*" },
    { Effect = "Allow", Action = "logs:DescribeLogGroups", Resource = "${local.logs}:log-group:*" }
  ] })
}
resource "aws_iam_role_policy" "model" {
  for_each = local.stages
  role     = aws_iam_role.runtime[each.key].id
  name     = "model"
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "bedrock:InvokeModel", Resource = concat([data.aws_bedrock_inference_profile.model.inference_profile_arn], [for m in data.aws_bedrock_inference_profile.model.models : m.model_arn])
  }] })
}
resource "aws_bedrockagentcore_agent_runtime" "worker" {
  for_each              = local.stages
  agent_runtime_name    = "groupchat_${each.key}"
  description           = "Group chat menu meeting role: ${each.key}"
  role_arn              = aws_iam_role.runtime[each.key].arn
  environment_variables = { ROLE = each.key, MODEL_ID = var.model_id, SAMPLE_REGION = var.aws_region, DATA_BUCKET = aws_s3_bucket.artifacts.id }
  agent_runtime_artifact {
    code_configuration {
      runtime     = "PYTHON_3_14"
      entry_point = ["worker.py"]
      code {
        s3 {
          bucket = aws_s3_bucket.code.id
          prefix = aws_s3_object.code["worker"].key
        }
      }
    }
  }
  network_configuration { network_mode = "PUBLIC" }
  protocol_configuration { server_protocol = "A2A" }
  lifecycle_configuration {
    idle_runtime_session_timeout = 60
    max_lifetime                 = 600
  }
  depends_on = [aws_iam_role_policy.base, aws_iam_role_policy.model, aws_iam_role_policy.data]
}
resource "aws_iam_role_policy" "pipeline" {
  role = aws_iam_role.runtime["pipeline"].id
  name = "workers_and_artifacts"
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "bedrock-agentcore:InvokeAgentRuntime", Resource = flatten([for r in aws_bedrockagentcore_agent_runtime.worker : [r.agent_runtime_arn, "${r.agent_runtime_arn}/runtime-endpoint/*"]]) },
    { Effect = "Allow", Action = "s3:PutObject", Resource = "${aws_s3_bucket.artifacts.arn}/runs/*/manifest.json" },
    { Effect = "Allow", Action = ["bedrock-agentcore:CreateEvent", "bedrock-agentcore:GetEvent"], Resource = aws_bedrockagentcore_memory.meeting.arn }
  ] })
}
resource "aws_bedrockagentcore_agent_runtime" "pipeline" {
  agent_runtime_name = "groupchat_pipeline"
  description        = "Bounded group chat chair; no model permissions"
  role_arn           = aws_iam_role.runtime["pipeline"].arn
  environment_variables = {
    SAMPLE_REGION   = var.aws_region
    MEMORY_ID       = aws_bedrockagentcore_memory.meeting.id
    ARTIFACT_BUCKET = aws_s3_bucket.artifacts.id
    WORKER_ARNS     = jsonencode({ for k, r in aws_bedrockagentcore_agent_runtime.worker : k => r.agent_runtime_arn })
  }
  agent_runtime_artifact {
    code_configuration {
      runtime     = "PYTHON_3_14"
      entry_point = ["pipeline.py"]
      code {
        s3 {
          bucket = aws_s3_bucket.code.id
          prefix = aws_s3_object.code["pipeline"].key
        }
      }
    }
  }
  network_configuration { network_mode = "PUBLIC" }
  protocol_configuration { server_protocol = "HTTP" }
  lifecycle_configuration {
    idle_runtime_session_timeout = 60
    max_lifetime                 = 1800
  }
  depends_on = [aws_iam_role_policy.base, aws_iam_role_policy.pipeline]
}
output "client_config" {
  value = {
    aws_profile     = var.aws_profile, aws_region = var.aws_region, model_id = var.model_id
    pipeline_arn    = aws_bedrockagentcore_agent_runtime.pipeline.agent_runtime_arn
    workers         = { for k, r in aws_bedrockagentcore_agent_runtime.worker : k => r.agent_runtime_arn }
    runtime_ids     = merge({ pipeline = aws_bedrockagentcore_agent_runtime.pipeline.agent_runtime_id }, { for k, r in aws_bedrockagentcore_agent_runtime.worker : k => r.agent_runtime_id })
    memory_id       = aws_bedrockagentcore_memory.meeting.id
    artifact_bucket = aws_s3_bucket.artifacts.id
    code_bucket     = aws_s3_bucket.code.id
    role_names      = [for r in aws_iam_role.runtime : r.name]
  }
}

resource "aws_iam_role_policy" "data" {
  for_each = local.stages
  role     = aws_iam_role.runtime[each.key].id
  name     = "own_inputs_and_outputs"
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "s3:GetObject", Resource = concat(
      ["${aws_s3_bucket.artifacts.arn}/runs/*/inputs/common.md"],
      each.key == "summary" ? [] : ["${aws_s3_bucket.artifacts.arn}/runs/*/inputs/${each.key}.md"]
    ) },
    { Effect = "Allow", Action = "s3:PutObject", Resource = "${aws_s3_bucket.artifacts.arn}/runs/*/${each.key}/*" }
  ] })
}

resource "aws_bedrockagentcore_memory" "meeting" {
  name                  = "groupchat_meeting"
  description           = "Short-term shared menu meeting transcript; no extraction strategies"
  event_expiry_duration = 7
}
