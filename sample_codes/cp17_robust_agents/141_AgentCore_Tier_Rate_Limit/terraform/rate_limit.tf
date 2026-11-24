locals {
  rate_limit_id  = "add-per-minute"
  tool_name      = "${local.target_name}___add"
  tenant_tiers   = { tenant-a = "free", tenant-b = "free", tenant-c = "pro" }
  demo_users     = { alice = "tenant-a", alice2 = "tenant-a", bob = "tenant-b", carol = "tenant-c" }
  tier_rates     = { free = 2, pro = 10 }
  dimension_keys = ["toolName", "$.context.jwt.tier", "$.context.jwt.tenant_id"]
}

# AWS provider 6.66.0 has no native GatewayRateLimit resource.
# CloudFormation owns the rate limit; Terraform owns its stack lifecycle.
resource "aws_cloudformation_stack" "rate_limit" {
  name = "${local.gateway_name}-rate-limit"
  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Resources = {
      AddRateLimit = {
        Type = "AWS::BedrockAgentCore::GatewayRateLimit"
        Properties = {
          GatewayIdentifier = aws_bedrockagentcore_gateway.calculator.gateway_id
          RateLimitId       = local.rate_limit_id
          Description       = "Tenant-shared add limits selected by trusted JWT tier"
          DimensionKeys     = local.dimension_keys
          Entries = [for tier, rate in local.tier_rates : {
            Dimensions = { toolName = local.tool_name, "$.context.jwt.tier" = tier, "$.context.jwt.tenant_id" = "*" }
            Requests   = [{ Rate = rate, Period = "minute" }]
          }]
        }
      }
    }
  })
  depends_on = [aws_bedrockagentcore_gateway_target.calculator]
}

output "rate_limit_config" {
  value = {
    id             = local.rate_limit_id
    tool_name      = local.tool_name
    dimension_keys = local.dimension_keys
    tier_rates     = local.tier_rates
    tenant_tiers   = local.tenant_tiers
    stack_name     = aws_cloudformation_stack.rate_limit.name
  }
}
