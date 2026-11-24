locals {
  runtime_url = "https://bedrock-agentcore.${var.aws_region}.amazonaws.com/runtimes/${urlencode(aws_bedrockagentcore_agent_runtime.demo.agent_runtime_arn)}/invocations?qualifier=DEFAULT"
}
output "gateway_id" { value = aws_bedrockagentcore_gateway.demo.gateway_id }
output "target_id" { value = aws_bedrockagentcore_gateway_target.demo.target_id }
output "runtime_arn" { value = aws_bedrockagentcore_agent_runtime.demo.agent_runtime_arn }
output "runtime_log_group" { value = "/aws/bedrock-agentcore/runtimes/${aws_bedrockagentcore_agent_runtime.demo.agent_runtime_id}-DEFAULT" }
output "client_config" {
  value = {
    aws_profile  = var.aws_profile
    aws_region   = var.aws_region
    user_pool_id = aws_cognito_user_pool.users.id
    client_id    = aws_cognito_user_pool_client.local.id
    login_base   = local.login_base
    callback_url = local.callback_url
    logout_url   = local.logout_url
    scopes       = ["openid", local.invoke_scope]
    mcp_url      = aws_bedrockagentcore_gateway.demo.gateway_url
    tool_prefix  = "${local.target_name}___"
  }
}
output "codex_mcp_config" {
  value = <<-TOML
    [mcp_servers.agentcore-infisical]
    url = "${aws_bedrockagentcore_gateway.demo.gateway_url}"
    scopes = ["openid", "${local.invoke_scope}"]
    startup_timeout_sec = 120
    tool_timeout_sec = 180
    [mcp_servers.agentcore-infisical.oauth]
    client_id = "${aws_cognito_user_pool_client.local.id}"
    callback_port = 8766
    callback_url = "${coalesce(var.codex_oauth_callback_url, "http://localhost:8766/callback")}"
  TOML
}

output "mcp_url" { value = aws_bedrockagentcore_gateway.demo.gateway_url }
output "claude_mcp_config" {
  value = jsonencode({ mcpServers = { "agentcore-infisical" = {
    type  = "http"
    url   = aws_bedrockagentcore_gateway.demo.gateway_url
    oauth = { clientId = aws_cognito_user_pool_client.local.id, callbackPort = 8767 }
  } } })
}
