output "mcp_url" { value = aws_bedrockagentcore_gateway.demo.gateway_url }
output "client_config" {
  value = {
    aws_profile       = var.aws_profile
    aws_region        = var.aws_region
    user_pool_id      = aws_cognito_user_pool.users.id
    client_id         = aws_cognito_user_pool_client.local.id
    login_base        = local.login_base
    callback_url      = local.callback_url
    logout_url        = local.logout_url
    scopes            = ["openid", local.invoke_scope]
    mcp_url           = aws_bedrockagentcore_gateway.demo.gateway_url
    tool_name         = "${local.target_name}___Retrieve"
    knowledge_base_id = aws_bedrockagent_knowledge_base.shared.id
    data_source_id    = aws_bedrockagent_data_source.documents.data_source_id
  }
}
output "codex_mcp_config" {
  value = <<-TOML
    [mcp_servers.agentcore-kb-tenant]
    url = "${aws_bedrockagentcore_gateway.demo.gateway_url}"
    scopes = ["openid", "${local.invoke_scope}"]
    startup_timeout_sec = 120
    tool_timeout_sec = 180
    [mcp_servers.agentcore-kb-tenant.oauth]
    client_id = "${aws_cognito_user_pool_client.local.id}"
    callback_port = 8766
    callback_url = "${coalesce(var.codex_oauth_callback_url, "http://localhost:8766/callback")}"
  TOML
}
output "claude_mcp_config" {
  value = jsonencode({ mcpServers = { agentcore-kb-tenant = {
    type = "http", url = aws_bedrockagentcore_gateway.demo.gateway_url,
    oauth = { clientId = aws_cognito_user_pool_client.local.id, callbackPort = local.claude_callback_port,
    scopes = "openid ${local.invoke_scope}", authServerMetadataUrl = "${local.issuer}/.well-known/openid-configuration" }
  } } })
}
