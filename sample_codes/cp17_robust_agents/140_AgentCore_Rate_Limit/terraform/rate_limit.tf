locals {
  rate_limit_id = "add-per-minute"
  tool_name     = "${local.target_name}___add"
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
          Description       = "Shared add tool limit: configured requests per minute for all callers"
          DimensionKeys     = ["toolName"]
          Entries = [{
            Dimensions = { toolName = local.tool_name }
            Requests   = [{ Rate = var.requests_per_minute, Period = "minute" }]
          }]
        }
      }
    }
  })
  depends_on = [aws_bedrockagentcore_gateway_target.calculator]
}

output "rate_limit_config" {
  value = {
    id                  = local.rate_limit_id
    tool_name           = local.tool_name
    requests_per_minute = var.requests_per_minute
    stack_name          = aws_cloudformation_stack.rate_limit.name
  }
}
