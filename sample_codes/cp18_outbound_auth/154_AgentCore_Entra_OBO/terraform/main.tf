terraform {
  required_version = ">= 1.14, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "= 6.71.0" }
  }
  backend "local" { path = "terraform.tfstate" }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
  default_tags { tags = { Project = "entra-graph-obo", ManagedBy = "Terraform" } }
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}
variable "aws_profile" {
  type    = string
  default = "develop"
}
variable "name" {
  type    = string
  default = "entra-graph-obo"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,24}$", var.name))
    error_message = "Use a lowercase name of at most 25 characters."
  }
}
variable "tenant_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.tenant_id))
    error_message = "Specify the Entra tenant GUID."
  }
}
variable "api_client_id" { type = string }
variable "local_client_id" { type = string }
variable "secret_name" { type = string }
variable "gateway_debug" {
  type    = bool
  default = false
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
# Metadata only: never read aws_secretsmanager_secret_version / SecretString.
data "aws_secretsmanager_secret" "entra" { name = var.secret_name }

locals {
  prefix = "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  issuer = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
  workload_resources = [
    "${local.prefix}:workload-identity-directory/default",
    "${local.prefix}:workload-identity-directory/default/workload-identity/${var.name}-*"
  ]
}

# AWS provider 6.71.0 supports EXTERNAL: only the reference enters state.
# The Microsoft provider supplies JWT_AUTHORIZATION_GRANT / on_behalf_of itself.
resource "aws_bedrockagentcore_oauth2_credential_provider" "entra" {
  name                       = "${var.name}-microsoft"
  credential_provider_vendor = "MicrosoftOauth2"
  oauth2_provider_config {
    microsoft_oauth2_provider_config {
      client_id            = var.api_client_id
      tenant_id            = var.tenant_id
      client_secret_source = "EXTERNAL"
      client_secret_config {
        secret_id = data.aws_secretsmanager_secret.entra.arn
        json_key  = "clientSecret"
      }
    }
  }
}

resource "aws_iam_role" "gateway" {
  name = "${var.name}-gateway"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Service = "bedrock-agentcore.amazonaws.com" }, Action = "sts:AssumeRole",
    Condition = {
      StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      ArnLike      = { "aws:SourceArn" = "${local.prefix}:gateway/${var.name}-*" }
    }
  }] })
}
resource "aws_iam_role_policy" "gateway" {
  name = "${var.name}-outbound"
  role = aws_iam_role.gateway.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT"], Resource = local.workload_resources },
    { Effect = "Allow", Action = ["bedrock-agentcore:GetResourceOauth2Token"], Resource = concat(local.workload_resources, ["${local.prefix}:token-vault/default", aws_bedrockagentcore_oauth2_credential_provider.entra.credential_provider_arn]) },
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [data.aws_secretsmanager_secret.entra.arn] }
  ] })
}

resource "aws_bedrockagentcore_gateway" "graph" {
  name            = var.name
  role_arn        = aws_iam_role.gateway.arn
  authorizer_type = "CUSTOM_JWT"
  protocol_type   = "MCP"
  exception_level = var.gateway_debug ? "DEBUG" : null
  authorizer_configuration {
    custom_jwt_authorizer {
      discovery_url    = "${local.issuer}/.well-known/openid-configuration"
      allowed_audience = [var.api_client_id]
      allowed_scopes   = ["access_as_user"]
      # Live AWS validation reserves scp for allowed_scopes. Entra azp stays explicit.
      dynamic "custom_claim" {
        for_each = { azp = var.local_client_id, ver = "2.0", tid = var.tenant_id }
        content {
          inbound_token_claim_name       = custom_claim.key
          inbound_token_claim_value_type = "STRING"
          authorizing_claim_match_value {
            claim_match_operator = "EQUALS"
            claim_match_value { match_value_string = custom_claim.value }
          }
        }
      }
    }
  }
  protocol_configuration {
    mcp { supported_versions = ["2025-11-25"] }
  }
  depends_on = [aws_iam_role_policy.gateway]
}

resource "aws_bedrockagentcore_gateway_target" "graph" {
  name               = "graph"
  gateway_identifier = aws_bedrockagentcore_gateway.graph.gateway_id
  credential_provider_configuration {
    oauth {
      provider_arn = aws_bedrockagentcore_oauth2_credential_provider.entra.credential_provider_arn
      grant_type   = "TOKEN_EXCHANGE"
      scopes       = ["https://graph.microsoft.com/.default"]
    }
  }
  target_configuration {
    mcp {
      open_api_schema {
        inline_payload { payload = file("${path.module}/graph.openapi.json") }
      }
    }
  }
}

output "client_config" {
  value = {
    aws_region        = var.aws_region
    aws_profile       = var.aws_profile
    tenant_id         = var.tenant_id
    api_client_id     = var.api_client_id
    local_client_id   = var.local_client_id
    scope             = "api://${var.api_client_id}/access_as_user"
    gateway_url       = aws_bedrockagentcore_gateway.graph.gateway_url
    gateway_id        = aws_bedrockagentcore_gateway.graph.gateway_id
    tool_name         = "graph___get_my_profile"
    provider_name     = aws_bedrockagentcore_oauth2_credential_provider.entra.name
    provider_arn      = aws_bedrockagentcore_oauth2_credential_provider.entra.credential_provider_arn
    workload_arn      = aws_bedrockagentcore_gateway.graph.workload_identity_details[0].workload_identity_arn
    source_secret_arn = data.aws_secretsmanager_secret.entra.arn
  }
}
