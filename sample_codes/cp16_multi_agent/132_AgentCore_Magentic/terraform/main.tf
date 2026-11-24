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
  default_tags { tags = { Project = "magentic", ManagedBy = "Terraform" } }
}
data "aws_caller_identity" "current" {}
data "aws_bedrock_inference_profile" "model" { inference_profile_id = var.model_id }
locals {
  roles      = toset(["manager", "repair", "insurance", "rental"])
  workers    = toset(["repair", "insurance", "rental"])
  prefix     = "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  logs       = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  build_hash = sha256(jsonencode({ for f in ["app/specialist.py", "app/manager.py", "app/contracts.py", "app/store.py", "app/transport.py", "app/orchestration.py", "app/facts.py", "app/model.py", "scripts/build.py", "pyproject.toml", "uv.lock"] : f => filesha256("${path.module}/../${f}") }))
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
  bucket_prefix = "magentic-code-"
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
  for_each    = toset(["specialist", "manager"])
  bucket      = aws_s3_bucket.code.id
  key         = "${each.key}/${local.build_hash}.zip"
  source      = "${path.module}/../build/${each.key}.zip"
  source_hash = terraform_data.build.id
  depends_on  = [aws_s3_bucket_public_access_block.code, aws_s3_bucket_server_side_encryption_configuration.code]
}
resource "aws_iam_role" "runtime" {
  for_each           = local.roles
  name               = "magentic_${each.key}"
  assume_role_policy = local.assume
}
resource "aws_iam_role_policy" "base" {
  for_each = local.roles
  role     = aws_iam_role.runtime[each.key].id
  name     = "code_and_logs"
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "s3:GetObject", Resource = "${aws_s3_bucket.code.arn}/${each.key == "manager" ? "manager" : "specialist"}/*" },
    { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:DescribeLogStreams", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${local.logs}:log-group:/aws/bedrock-agentcore/runtimes/magentic_${each.key}-*" },
    { Effect = "Allow", Action = "logs:DescribeLogGroups", Resource = "${local.logs}:log-group:*" }
  ] })
}
resource "aws_iam_role_policy" "model" {
  for_each = local.roles
  role     = aws_iam_role.runtime[each.key].id
  name     = "model"
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "bedrock:InvokeModel", Resource = concat([data.aws_bedrock_inference_profile.model.inference_profile_arn], [for m in data.aws_bedrock_inference_profile.model.models : m.model_arn])
  }] })
}

resource "aws_s3_bucket" "data" {
  bucket_prefix = "magentic-data-"
  force_destroy = true
}
resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_object" "fixture" {
  for_each     = local.workers
  bucket       = aws_s3_bucket.data.id
  key          = "fixtures/${each.key}.json"
  source       = "${path.module}/../fixtures/${each.key}.json"
  source_hash  = filesha256("${path.module}/../fixtures/${each.key}.json")
  content_type = "application/json"
  depends_on   = [aws_s3_bucket_public_access_block.data, aws_s3_bucket_server_side_encryption_configuration.data]
}
resource "aws_dynamodb_table" "state" {
  name         = "magentic-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "case_id"
  attribute {
    name = "case_id"
    type = "S"
  }
}
resource "aws_iam_role_policy" "facts" {
  for_each = local.workers
  role     = aws_iam_role.runtime[each.key].id
  name     = "own_fixture"
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "s3:GetObject", Resource = "${aws_s3_bucket.data.arn}/fixtures/${each.key}.json"
  }] })
}
resource "aws_bedrockagentcore_agent_runtime" "specialist" {
  for_each           = local.workers
  agent_runtime_name = "magentic_${each.key}"
  role_arn           = aws_iam_role.runtime[each.key].arn
  environment_variables = {
    ROLE = each.key, SAMPLE_REGION = var.aws_region, MODEL_ID = var.model_id, DATA_BUCKET = aws_s3_bucket.data.id
  }
  agent_runtime_artifact {
    code_configuration {
      runtime     = "PYTHON_3_14"
      entry_point = ["specialist.py"]
      code {
        s3 {
          bucket = aws_s3_bucket.code.id
          prefix = aws_s3_object.code["specialist"].key
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
  depends_on = [aws_iam_role_policy.base, aws_iam_role_policy.model, aws_iam_role_policy.facts, aws_s3_object.fixture]
}
resource "aws_iam_role_policy" "manager" {
  role = aws_iam_role.runtime["manager"].id
  name = "specialists_and_ledger"
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "bedrock-agentcore:InvokeAgentRuntime", Resource = flatten([for r in aws_bedrockagentcore_agent_runtime.specialist : [r.agent_runtime_arn, "${r.agent_runtime_arn}/runtime-endpoint/*"]]) },
    { Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"], Resource = aws_dynamodb_table.state.arn }
  ] })
}
resource "aws_bedrockagentcore_agent_runtime" "manager" {
  agent_runtime_name = "magentic_manager"
  role_arn           = aws_iam_role.runtime["manager"].arn
  environment_variables = {
    SAMPLE_REGION   = var.aws_region, MODEL_ID = var.model_id, STATE_TABLE = aws_dynamodb_table.state.name,
    SPECIALIST_ARNS = jsonencode({ for k, r in aws_bedrockagentcore_agent_runtime.specialist : k => r.agent_runtime_arn })
  }
  agent_runtime_artifact {
    code_configuration {
      runtime     = "PYTHON_3_14"
      entry_point = ["manager.py"]
      code {
        s3 {
          bucket = aws_s3_bucket.code.id
          prefix = aws_s3_object.code["manager"].key
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
  depends_on = [aws_iam_role_policy.base, aws_iam_role_policy.model, aws_iam_role_policy.manager]
}
output "client_config" {
  value = {
    aws_profile = var.aws_profile, aws_region = var.aws_region, model_id = var.model_id,
    manager_arn = aws_bedrockagentcore_agent_runtime.manager.agent_runtime_arn,
    specialists = { for k, r in aws_bedrockagentcore_agent_runtime.specialist : k => r.agent_runtime_arn },
    runtime_ids = merge({ manager = aws_bedrockagentcore_agent_runtime.manager.agent_runtime_id }, { for k, r in aws_bedrockagentcore_agent_runtime.specialist : k => r.agent_runtime_id }),
    state_table = aws_dynamodb_table.state.name, data_bucket = aws_s3_bucket.data.id, code_bucket = aws_s3_bucket.code.id,
    role_names  = [for r in aws_iam_role.runtime : r.name]
  }
}
