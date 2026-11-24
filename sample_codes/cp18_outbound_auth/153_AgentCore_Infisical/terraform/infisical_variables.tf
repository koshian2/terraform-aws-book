variable "infisical_host" {
  type    = string
  default = "https://app.infisical.com"
  validation {
    condition     = contains(["https://app.infisical.com", "https://us.infisical.com", "https://eu.infisical.com"], var.infisical_host)
    error_message = "Use a supported Infisical Cloud host."
  }
}
variable "infisical_organization_id" { type = string }
variable "infisical_manager_identity_id" { type = string }
