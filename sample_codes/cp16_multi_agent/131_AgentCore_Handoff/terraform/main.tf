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
  default_tags { tags = { Project = "handoff", ManagedBy = "Terraform" } }
}
data "aws_caller_identity" "current" {}
data "aws_bedrock_inference_profile" "model" { inference_profile_id = var.model_id }
locals {
  roles      = toset(["router", "predecessor", "successor"])
  workers    = toset(["predecessor", "successor"])
  prefix     = "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  logs       = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  build_hash = sha256(jsonencode({ for f in ["app/worker.py", "app/router.py", "app/contracts.py", "app/store.py", "app/transport.py", "app/handoff.py", "scripts/build.py", "pyproject.toml", "uv.lock"] : f => filesha256("${path.module}/../${f}") }))
  assume = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Action = "sts:AssumeRole", Principal = { Service = "bedrock-agentcore.amazonaws.com" },
    Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }, ArnLike = { "aws:SourceArn" = "${local.prefix}:*" } }
  }] })
}
resource "terraform_data" "build" {
  triggers_replace = local.build_hash
  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = "uv run --frozen python scripts/build.py"
  }
}
resource "aws_s3_bucket" "code" {
  bucket_prefix = "handoff-code-"
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
  for_each    = toset(["worker", "router"])
  bucket      = aws_s3_bucket.code.id
  key         = "${each.key}/${local.build_hash}.zip"
  source      = "${path.module}/../build/${each.key}.zip"
  source_hash = terraform_data.build.id
  depends_on  = [aws_s3_bucket_public_access_block.code, aws_s3_bucket_server_side_encryption_configuration.code]
}
resource "aws_dynamodb_table" "cases" {
  for_each     = toset(["state", "private", "inbox"])
  name         = "handoff-${each.key}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "case_id"
  attribute {
    name = "case_id"
    type = "S"
  }
}
resource "aws_iam_role" "runtime" {
  for_each           = local.roles
  name               = "handoff_${each.key}"
  assume_role_policy = local.assume
}
resource "aws_iam_role_policy" "base" {
  for_each = local.roles
  role     = aws_iam_role.runtime[each.key].id
  name     = "code_and_logs"
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "s3:GetObject", Resource = "${aws_s3_bucket.code.arn}/${each.key == "router" ? "router" : "worker"}/*" },
    { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:DescribeLogStreams", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${local.logs}:log-group:/aws/bedrock-agentcore/runtimes/handoff_${each.key}-*" },
    { Effect = "Allow", Action = "logs:DescribeLogGroups", Resource = "${local.logs}:log-group:*" }
  ] })
}
resource "aws_iam_role_policy" "model" {
  for_each = local.workers
  role     = aws_iam_role.runtime[each.key].id
  name     = "model"
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "bedrock:InvokeModel", Resource = concat([data.aws_bedrock_inference_profile.model.inference_profile_arn], [for m in data.aws_bedrock_inference_profile.model.models : m.model_arn])
  }] })
}
resource "aws_iam_role_policy" "data" {
  for_each = local.roles
  role     = aws_iam_role.runtime[each.key].id
  name     = "case_records"
  policy = jsonencode({ Version = "2012-10-17", Statement = concat(
    [{ Effect = "Allow", Action = "dynamodb:GetItem", Resource = aws_dynamodb_table.cases["state"].arn }],
    each.key == "router" ? [{ Effect = "Allow", Action = "dynamodb:PutItem", Resource = [aws_dynamodb_table.cases["state"].arn, aws_dynamodb_table.cases["private"].arn] }] : [],
    each.key == "predecessor" ? [
      { Effect = "Allow", Action = "dynamodb:GetItem", Resource = aws_dynamodb_table.cases["private"].arn },
      { Effect = "Allow", Action = "dynamodb:UpdateItem", Resource = aws_dynamodb_table.cases["state"].arn }
    ] : [],
    each.key == "successor" ? [
      { Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:PutItem"], Resource = aws_dynamodb_table.cases["inbox"].arn }
    ] : []
  ) })
}
resource "aws_bedrockagentcore_agent_runtime" "successor" {
  agent_runtime_name = "handoff_successor"
  role_arn           = aws_iam_role.runtime["successor"].arn
  environment_variables = {
    ROLE        = "successor", SAMPLE_REGION = var.aws_region, MODEL_ID = var.model_id,
    STATE_TABLE = aws_dynamodb_table.cases["state"].name, INBOX_TABLE = aws_dynamodb_table.cases["inbox"].name
  }
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
  depends_on = [aws_iam_role_policy.base, aws_iam_role_policy.data, aws_iam_role_policy.model]
}
resource "aws_iam_role_policy" "handoff" {
  role = aws_iam_role.runtime["predecessor"].id
  name = "invoke_successor"
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect   = "Allow", Action = "bedrock-agentcore:InvokeAgentRuntime",
    Resource = [aws_bedrockagentcore_agent_runtime.successor.agent_runtime_arn, "${aws_bedrockagentcore_agent_runtime.successor.agent_runtime_arn}/runtime-endpoint/*"]
  }] })
}
resource "aws_bedrockagentcore_agent_runtime" "predecessor" {
  agent_runtime_name = "handoff_predecessor"
  role_arn           = aws_iam_role.runtime["predecessor"].arn
  environment_variables = {
    ROLE          = "predecessor", SAMPLE_REGION = var.aws_region, MODEL_ID = var.model_id,
    STATE_TABLE   = aws_dynamodb_table.cases["state"].name, PRIVATE_TABLE = aws_dynamodb_table.cases["private"].name,
    SUCCESSOR_ARN = aws_bedrockagentcore_agent_runtime.successor.agent_runtime_arn
  }
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
  depends_on = [aws_iam_role_policy.base, aws_iam_role_policy.data, aws_iam_role_policy.model, aws_iam_role_policy.handoff]
}
locals {
  workers_map = { predecessor = aws_bedrockagentcore_agent_runtime.predecessor, successor = aws_bedrockagentcore_agent_runtime.successor }
}
resource "aws_iam_role_policy" "router" {
  role = aws_iam_role.runtime["router"].id
  name = "invoke_current_representative"
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect   = "Allow", Action = "bedrock-agentcore:InvokeAgentRuntime",
    Resource = flatten([for r in local.workers_map : [r.agent_runtime_arn, "${r.agent_runtime_arn}/runtime-endpoint/*"]])
  }] })
}
resource "aws_bedrockagentcore_agent_runtime" "router" {
  agent_runtime_name = "handoff_router"
  role_arn           = aws_iam_role.runtime["router"].arn
  environment_variables = {
    SAMPLE_REGION = var.aws_region, STATE_TABLE = aws_dynamodb_table.cases["state"].name,
    PRIVATE_TABLE = aws_dynamodb_table.cases["private"].name,
    WORKER_ARNS   = jsonencode({ for k, r in local.workers_map : k => r.agent_runtime_arn })
  }
  agent_runtime_artifact {
    code_configuration {
      runtime     = "PYTHON_3_14"
      entry_point = ["router.py"]
      code {
        s3 {
          bucket = aws_s3_bucket.code.id
          prefix = aws_s3_object.code["router"].key
        }
      }
    }
  }
  network_configuration { network_mode = "PUBLIC" }
  protocol_configuration { server_protocol = "HTTP" }
  lifecycle_configuration {
    idle_runtime_session_timeout = 60
    max_lifetime                 = 600
  }
  depends_on = [aws_iam_role_policy.base, aws_iam_role_policy.data, aws_iam_role_policy.router]
}
output "client_config" {
  value = {
    aws_profile = var.aws_profile, aws_region = var.aws_region, model_id = var.model_id,
    router_arn  = aws_bedrockagentcore_agent_runtime.router.agent_runtime_arn,
    workers     = { for k, r in local.workers_map : k => r.agent_runtime_arn },
    runtime_ids = merge({ router = aws_bedrockagentcore_agent_runtime.router.agent_runtime_id }, { for k, r in local.workers_map : k => r.agent_runtime_id }),
    tables      = { for k, t in aws_dynamodb_table.cases : k => t.name },
    code_bucket = aws_s3_bucket.code.id, role_names = [for r in aws_iam_role.runtime : r.name]
  }
}
