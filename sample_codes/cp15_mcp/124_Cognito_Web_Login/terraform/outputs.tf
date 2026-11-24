output "web_url" { value = local.site_url }
output "settings" {
  value = {
    aws_profile  = var.aws_profile
    aws_region   = var.aws_region
    user_pool_id = aws_cognito_user_pool.users.id
    client_id    = aws_cognito_user_pool_client.python.id
    issuer       = local.issuer
  }
}
