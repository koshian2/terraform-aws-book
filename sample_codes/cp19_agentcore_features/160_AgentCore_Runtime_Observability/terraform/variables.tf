variable "aws_profile" {
  type    = string
  default = "develop"
}


variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "name" {
  type    = string
  default = "quote_observability_mcp"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,39}$", var.name))
    error_message = "name must start with a letter and contain up to 40 letters, digits, or underscores."
  }
}
