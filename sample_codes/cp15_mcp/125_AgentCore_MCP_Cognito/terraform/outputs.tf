locals {
  mcp_url = "https://bedrock-agentcore.${var.aws_region}.amazonaws.com/runtimes/${urlencode(aws_bedrockagentcore_agent_runtime.hello.agent_runtime_arn)}/invocations?qualifier=DEFAULT"
}

output "runtime_arn" {
  value = aws_bedrockagentcore_agent_runtime.hello.agent_runtime_arn
}
output "mcp_url" {
  value = local.mcp_url
}
output "user_pool_id" {
  value = aws_cognito_user_pool.users.id
}
output "client_config" {
  description = "Public configuration only; no passwords or tokens."
  value = {
    aws_profile    = var.aws_profile
    aws_region     = var.aws_region
    user_pool_id   = aws_cognito_user_pool.users.id
    client_id      = aws_cognito_user_pool_client.local.id
    login_base     = local.login_base
    callback_url   = local.callback_url
    scopes         = ["openid", local.invoke_scope]
    mcp_url        = local.mcp_url
    log_group_name = "/aws/bedrock-agentcore/runtimes/${aws_bedrockagentcore_agent_runtime.hello.agent_runtime_id}-DEFAULT"
  }
}
output "codex_mcp_config" {
  value = <<-TOML
    [mcp_servers.agentcore-cognito]
    url = "${local.mcp_url}"
    scopes = ["openid", "${local.invoke_scope}"]
    startup_timeout_sec = 120
    tool_timeout_sec = 180

    [mcp_servers.agentcore-cognito.oauth]
    client_id = "${aws_cognito_user_pool_client.local.id}"
    callback_port = 8766
    callback_url = "${coalesce(var.codex_oauth_callback_url, "http://localhost:8766/callback")}"
  TOML
}

output "claude_mcp_config" {
  description = "Claude Code project configuration; no passwords or tokens."
  value = jsonencode({
    mcpServers = {
      agentcore-cognito = {
        type = "http"
        url  = local.mcp_url
        oauth = {
          clientId              = aws_cognito_user_pool_client.local.id
          callbackPort          = local.claude_callback_port
          scopes                = "openid ${local.invoke_scope}"
          authServerMetadataUrl = "${local.issuer}/.well-known/openid-configuration"
        }
      }
    }
  })
}
