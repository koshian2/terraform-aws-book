locals {
  runtime_url = "https://bedrock-agentcore.${var.aws_region}.amazonaws.com/runtimes/${urlencode(aws_bedrockagentcore_agent_runtime.demo.agent_runtime_arn)}/invocations?qualifier=DEFAULT"
}
output "gateway_id" { value = aws_bedrockagentcore_gateway.demo.gateway_id }
output "target_id" { value = aws_bedrockagentcore_gateway_target.demo.target_id }
output "product_table_name" { value = aws_dynamodb_table.products.name }
output "runtime_arn" { value = aws_bedrockagentcore_agent_runtime.demo.agent_runtime_arn }
output "runtime_log_group" { value = "/aws/bedrock-agentcore/runtimes/${aws_bedrockagentcore_agent_runtime.demo.agent_runtime_id}-DEFAULT" }
output "client_config" {
  value = {
    aws_profile    = var.aws_profile
    aws_region     = var.aws_region
    user_pool_id   = aws_cognito_user_pool.users.id
    client_id      = aws_cognito_user_pool_client.local.id
    login_base     = local.login_base
    callback_url   = local.callback_url
    logout_url     = local.logout_url
    scopes         = ["openid", local.invoke_scope]
    mcp_url        = aws_bedrockagentcore_gateway.demo.gateway_url
    runtime_id     = aws_bedrockagentcore_agent_runtime.demo.agent_runtime_id
    runtime_name   = var.name
    gateway_id     = aws_bedrockagentcore_gateway.demo.gateway_id
    log_group_name = "/aws/bedrock-agentcore/runtimes/${aws_bedrockagentcore_agent_runtime.demo.agent_runtime_id}-DEFAULT"
    tool_prefix    = "${local.target_name}___"
  }
}
