variable "github_repository" {
  type = string
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use a fixed owner/repository."
  }
}
variable "github_client_id" {
  type    = string
  default = "pending-registration"
}
variable "github_installation_id" {
  type    = number
  default = 0
  validation {
    condition     = var.github_installation_id >= 0 && floor(var.github_installation_id) == var.github_installation_id
    error_message = "Installation ID must be a nonnegative integer."
  }
}
variable "github_key_version" {
  type    = number
  default = 0
  validation {
    condition     = var.github_key_version >= 0 && floor(var.github_key_version) == var.github_key_version
    error_message = "Key version must be a nonnegative integer."
  }
}
variable "github_private_key" {
  type      = string
  sensitive = true
  ephemeral = true
  default   = ""
}

resource "aws_secretsmanager_secret" "github" {
  name_prefix = "${var.name}-private-key-"
  description = "GitHub App RSA private key for M2M (not an OAuth client secret)"
  # Sample-only: delete the secret along with the stack, without recovery delay.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "github" {
  count                    = var.github_key_version > 0 ? 1 : 0
  secret_id                = aws_secretsmanager_secret.github.id
  secret_string_wo         = var.github_private_key
  secret_string_wo_version = var.github_key_version
}

resource "aws_iam_role_policy" "github" {
  role = aws_iam_role.runtime.id
  name = "read_github_app_key"
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = aws_secretsmanager_secret.github.arn
  }] })
}
