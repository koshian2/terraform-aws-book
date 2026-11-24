# Reuse account-wide Transaction Search. Do not own aws/spans or its retention.
resource "aws_cloudwatch_log_delivery_source" "traces" {
  name         = "${local.gateway_name}-traces"
  log_type     = "TRACES"
  resource_arn = aws_bedrockagentcore_gateway.calculator.gateway_arn
}

resource "aws_cloudwatch_log_delivery_destination" "traces" {
  name                      = "${local.gateway_name}-xray"
  delivery_destination_type = "XRAY"
}

resource "aws_cloudwatch_log_delivery" "traces" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.traces.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.traces.arn
}

output "observation_config" {
  value = {
    aws_profile       = var.aws_profile
    aws_region        = var.aws_region
    gateway_id        = aws_bedrockagentcore_gateway.calculator.gateway_id
    gateway_arn       = aws_bedrockagentcore_gateway.calculator.gateway_arn
    policy_engine_id  = aws_bedrockagentcore_policy_engine.demo.policy_engine_id
    policy_engine_arn = aws_bedrockagentcore_policy_engine.demo.policy_engine_arn
    allow_policy_id   = aws_bedrockagentcore_policy.allow.policy_id
    deny_policy_id    = aws_bedrockagentcore_policy.deny.policy_id
    log_group         = "aws/spans"
  }
}
