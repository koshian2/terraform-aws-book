locals {
  issuer       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.users.id}"
  invoke_scope = "${aws_cognito_resource_server.mcp.identifier}/invoke"
  # The pool ID makes the hosted-domain prefix unique without another provider.
  login_base           = "https://${aws_cognito_user_pool_domain.login.domain}.auth.${var.aws_region}.amazoncognito.com"
  logout_url           = "http://localhost:8768/signed-out"
  callback_url         = "http://localhost:8765/callback"
  claude_callback_port = 8767
}

resource "aws_cognito_user_pool" "users" {
  name = "${var.name}_users"
  admin_create_user_config {
    allow_admin_create_user_only = true
  }
  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }
}

resource "aws_cognito_user_pool_domain" "login" {
  domain                = "mcp-${lower(replace(aws_cognito_user_pool.users.id, "_", "-"))}"
  user_pool_id          = aws_cognito_user_pool.users.id
  managed_login_version = 1 # Classic hosted UI; no branding resource is required.
}

resource "aws_cognito_resource_server" "mcp" {
  identifier   = "rate-limit"
  name         = "Calculator MCP"
  user_pool_id = aws_cognito_user_pool.users.id
  scope {
    scope_name        = "invoke"
    scope_description = "Invoke the Calculator MCP runtime"
  }
}

resource "aws_cognito_user_pool_client" "local" {
  name                                 = "${var.name}_local"
  user_pool_id                         = aws_cognito_user_pool.users.id
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", local.invoke_scope]
  callback_urls                        = [local.callback_url, coalesce(var.codex_oauth_callback_url, "http://localhost:8766/callback"), "http://localhost:${local.claude_callback_port}/callback"]
  default_redirect_uri                 = local.callback_url
  logout_urls                          = [local.logout_url]
  supported_identity_providers         = ["COGNITO"]
  explicit_auth_flows                  = ["ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  access_token_validity                = 60
  id_token_validity                    = 60
  refresh_token_validity               = 1
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}
