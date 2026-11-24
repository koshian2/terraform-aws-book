resource "infisical_project" "demo" {
  name                       = "AgentCore Workload Demo"
  slug                       = replace(var.name, "_", "-")
  type                       = "secret-manager"
  should_create_default_envs = true
}

# This identity has no organization administration privileges.
resource "infisical_identity" "runtime" {
  name   = "${var.name}-runtime"
  org_id = var.infisical_organization_id
  role   = "no-access"
}

resource "infisical_identity_aws_auth" "runtime" {
  identity_id              = infisical_identity.runtime.id
  sts_endpoint             = "https://sts.${var.aws_region}.amazonaws.com/"
  allowed_principal_arns   = [aws_iam_role.runtime.arn]
  allowed_account_ids      = []
  access_token_ttl         = 300
  access_token_max_ttl     = 300
  access_token_trusted_ips = [{ ip_address = "0.0.0.0/0" }]
}

resource "infisical_project_identity" "runtime" {
  project_id  = infisical_project.demo.id
  identity_id = infisical_identity.runtime.id
  roles       = [{ role_slug = "viewer" }]
}

resource "infisical_secret" "message" {
  workspace_id = infisical_project.demo.id
  env_slug     = "dev"
  folder_path  = "/"
  name         = "DEMO_MESSAGE"
  # Intentionally public demo content; never register real credentials here.
  value_wo         = "Hello from Infisical"
  value_wo_version = 1
}

output "infisical_project_url" {
  value = "${var.infisical_host}/organizations/${var.infisical_organization_id}/projects/secret-management/${infisical_project.demo.id}/overview"
}
output "runtime_identity_id" { value = infisical_identity.runtime.id }
output "runtime_role_arn" { value = aws_iam_role.runtime.arn }
