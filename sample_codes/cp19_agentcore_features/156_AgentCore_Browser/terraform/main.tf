terraform {
  required_version = ">= 1.11, < 2.0"
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

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
  default_tags {
    tags = { Project = "agentcore-browser-mcp", ManagedBy = "Terraform" }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "recordings" {
  bucket_prefix = "agentcore-mcp-browser-recordings-"
  force_destroy = true # destroy時に操作記録も削除する。
}
resource "aws_s3_bucket_public_access_block" "recordings" {
  bucket                  = aws_s3_bucket.recordings.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "recordings" {
  bucket = aws_s3_bucket.recordings.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_iam_role" "browser" {
  name_prefix = "browser-execution-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Principal = { Service = "bedrock-agentcore.amazonaws.com" }, Action = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}:browser-custom/*" }
      }
    }]
  })
}
resource "aws_iam_role_policy" "recordings" {
  role = aws_iam_role.browser.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.recordings.arn },
      { Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject", "s3:ListMultipartUploadParts", "s3:AbortMultipartUpload"], Resource = "${aws_s3_bucket.recordings.arn}/sessions/*" },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"], Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/browser/*" }
    ]
  })
}
resource "aws_bedrockagentcore_browser" "main" {
  name               = "mcp_browser"
  description        = "Browser controlled through local HTTP MCP"
  execution_role_arn = aws_iam_role.browser.arn
  network_configuration { network_mode = "PUBLIC" }
  recording {
    enabled = true
    s3_location {
      bucket = aws_s3_bucket.recordings.id
      prefix = "sessions/"
    }
  }
  depends_on = [aws_iam_role_policy.recordings, aws_s3_bucket_public_access_block.recordings, aws_s3_bucket_server_side_encryption_configuration.recordings]
}
output "client_config" {
  value = {
    aws_profile      = var.aws_profile
    aws_region       = var.aws_region
    browser_id       = aws_bedrockagentcore_browser.main.browser_id
    recording_bucket = aws_s3_bucket.recordings.id
    recording_prefix = "sessions/"
  }
}
