output "client_config" {
  value = {
    aws_profile       = var.aws_profile
    aws_region        = var.aws_region
    user_pool_id      = aws_cognito_user_pool.users.id
    client_id         = aws_cognito_user_pool_client.local.id
    login_base        = local.login_base
    callback_url      = "http://localhost:8765/callback"
    scopes            = ["openid", local.invoke_scope]
    mcp_url           = aws_bedrockagentcore_gateway.github.gateway_url
    gateway_id        = aws_bedrockagentcore_gateway.github.gateway_id
    target_id         = aws_bedrockagentcore_gateway_target.github.target_id
    tool_prefix       = "github-issues___"
    portal_url        = local.portal_url
    portal_id         = aws_cloudformation_stack.portal.outputs["PortalId"]
    portal_client_id  = aws_cloudformation_stack.portal.outputs["CognitoClientId"]
    idp_provider_name = aws_cloudformation_stack.portal.outputs["IdpProviderName"]
    provider_name     = aws_bedrockagentcore_oauth2_credential_provider.github.name
    github_callback   = aws_bedrockagentcore_oauth2_credential_provider.github.callback_url
    repository        = var.github_repository
    stack_name        = aws_cloudformation_stack.portal.name
  }
}
output "portal_url" { value = local.portal_url }
output "github_callback_url" { value = aws_bedrockagentcore_oauth2_credential_provider.github.callback_url }

output "mcp_url" { value = aws_bedrockagentcore_gateway.github.gateway_url }
output "claude_mcp_config" {
  value = jsonencode({ mcpServers = { "agentcore-github-consent" = {
    type  = "http"
    url   = aws_bedrockagentcore_gateway.github.gateway_url
    oauth = { clientId = aws_cognito_user_pool_client.local.id, callbackPort = 8767 }
  } } })
}
output "codex_mcp_config" {
  value = <<-TOML
 [mcp_servers.agentcore-github-consent]
 url = "${aws_bedrockagentcore_gateway.github.gateway_url}"
 scopes = ["openid", "${local.invoke_scope}"]
 startup_timeout_sec = 120
 tool_timeout_sec = 180
 [mcp_servers.agentcore-github-consent.oauth]
 client_id = "${aws_cognito_user_pool_client.local.id}"
 callback_port = 8766
 callback_url = "${coalesce(var.codex_oauth_callback_url, "http://localhost:8766/callback")}"
 TOML
}
