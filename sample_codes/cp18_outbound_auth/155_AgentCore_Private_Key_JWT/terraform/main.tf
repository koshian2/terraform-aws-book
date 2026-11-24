terraform {
  required_version = ">= 1.14, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "= 6.71.0" }
  }
}
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
  default_tags { tags = { Project = "entra-graph-private-key-jwt", ManagedBy = "Terraform" } }
}
variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}
variable "aws_profile" {
  type    = string
  default = "develop"
}
variable "tenant_id" { type = string }
variable "api_client_id" { type = string }
variable "m2m_client_id" { type = string }
variable "local_client_id" { type = string }
variable "key_arns" { type = map(string) }
variable "certificate_thumbprints" { type = map(string) }
variable "enable_obo" {
  type    = bool
  default = false
}
variable "gateway_debug" {
  type    = bool
  default = false
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
locals {
  name      = "entra-graph-pkjwt"
  prefix    = "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}"
  issuer    = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
  token_url = "https://login.microsoftonline.com/${var.tenant_id}/oauth2/v2.0/token"
  clients   = { obo = var.api_client_id, m2m = var.m2m_client_id }
  targets   = var.enable_obo ? toset(["m2m", "obo"]) : toset(["m2m"])
  workloads = ["${local.prefix}:workload-identity-directory/default", "${local.prefix}:workload-identity-directory/default/workload-identity/${local.name}-*"]
}
resource "aws_bedrockagentcore_oauth2_credential_provider" "entra" {
  for_each                   = local.clients
  name                       = "${local.name}-${each.key}"
  credential_provider_vendor = "CustomOauth2"
  oauth2_provider_config {
    custom_oauth2_provider_config {
      client_id                    = each.value
      client_authentication_method = "PRIVATE_KEY_JWT"
      oauth_discovery { discovery_url = "${local.issuer}/.well-known/openid-configuration" }
      private_key_jwt_config {
        signing_algorithm         = "PS256"
        additional_header_claims  = { "x5t#S256" = var.certificate_thumbprints[each.key] }
        additional_payload_claims = { aud = local.token_url }
        private_key_source {
          kms_key_source { kms_key_arn = var.key_arns[each.key] }
        }
      }
      dynamic "on_behalf_of_token_exchange_config" {
        for_each = each.key == "obo" ? [1] : []
        content { grant_type = "JWT_AUTHORIZATION_GRANT" }
      }
    }
  }
}
resource "aws_iam_role" "gateway" {
  name = "${local.name}-gateway"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Principal = { Service = "bedrock-agentcore.amazonaws.com" }, Action = "sts:AssumeRole",
    Condition = {
      StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      ArnLike      = { "aws:SourceArn" = "${local.prefix}:gateway/${local.name}-*" }
    }
  }] })
}
resource "aws_iam_role_policy" "gateway" {
  name = "${local.name}-outbound"
  role = aws_iam_role.gateway.id
  # Live Gateway error required kms:Sign in addition to the key policy.
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["bedrock-agentcore:GetWorkloadAccessToken", "bedrock-agentcore:GetWorkloadAccessTokenForJWT"], Resource = local.workloads },
    { Effect = "Allow", Action = ["bedrock-agentcore:GetResourceOauth2Token"], Resource = concat(local.workloads, ["${local.prefix}:token-vault/default"], [for p in aws_bedrockagentcore_oauth2_credential_provider.entra : p.credential_provider_arn]) },
    { Effect = "Allow", Action = ["kms:Sign"], Resource = values(var.key_arns), Condition = { StringEquals = { "kms:ViaService" = "bedrock-agentcore-identity.${var.aws_region}.amazonaws.com" } } }
  ] })
}
resource "aws_bedrockagentcore_gateway" "graph" {
  name            = local.name
  role_arn        = aws_iam_role.gateway.arn
  authorizer_type = "CUSTOM_JWT"
  protocol_type   = "MCP"
  exception_level = var.gateway_debug ? "DEBUG" : null
  authorizer_configuration {
    custom_jwt_authorizer {
      discovery_url    = "${local.issuer}/.well-known/openid-configuration"
      allowed_audience = [var.api_client_id]
      allowed_scopes   = ["access_as_user"]
      dynamic "custom_claim" {
        for_each = { azp = var.local_client_id, tid = var.tenant_id, ver = "2.0" }
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
  for_each           = local.targets
  name               = each.key
  gateway_identifier = aws_bedrockagentcore_gateway.graph.gateway_id
  credential_provider_configuration {
    oauth {
      provider_arn      = aws_bedrockagentcore_oauth2_credential_provider.entra[each.key].credential_provider_arn
      grant_type        = each.key == "obo" ? "TOKEN_EXCHANGE" : "CLIENT_CREDENTIALS"
      scopes            = ["https://graph.microsoft.com/.default"]
      custom_parameters = each.key == "obo" ? { requested_token_use = "on_behalf_of" } : null
    }
  }
  target_configuration {
    mcp {
      open_api_schema {
        inline_payload { payload = file("${path.module}/${each.key}.openapi.json") }
      }
    }
  }
}
output "client_config" {
  value = {
    aws_region  = var.aws_region, aws_profile = var.aws_profile,
    tenant_id   = var.tenant_id, api_client_id = var.api_client_id, local_client_id = var.local_client_id,
    scope       = "api://${var.api_client_id}/access_as_user",
    gateway_id  = aws_bedrockagentcore_gateway.graph.gateway_id,
    gateway_url = aws_bedrockagentcore_gateway.graph.gateway_url,
    enable_obo  = var.enable_obo,
    tool_names  = sort([for name in local.targets : name == "obo" ? "obo___get_my_profile" : "m2m___get_organization"])
  }
}
