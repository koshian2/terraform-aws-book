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
  default = "rate_limit_mcp"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,23}$", var.name))
    error_message = "nameは英字で始まる24文字以内の英数字とアンダースコアにしてください。"
  }
}
variable "codex_oauth_callback_url" {
  description = "Codexが表示したredirect_uriを登録します。"
  type        = string
  default     = null
  validation {
    condition     = var.codex_oauth_callback_url == null ? true : can(regex("^http://(localhost|127[.]0[.]0[.]1):8766/callback(/[A-Za-z0-9_-]+)?$", var.codex_oauth_callback_url))
    error_message = "http://localhost:8766/callback（127.0.0.1も可）またはその後ろにCodexのコールバックIDを付けて指定してください。"
  }
}


variable "requests_per_minute" {
  description = "Small positive demo limit shared across all callers of add."
  type        = number
  default     = 2
  validation {
    condition     = var.requests_per_minute >= 1 && var.requests_per_minute <= 10 && floor(var.requests_per_minute) == var.requests_per_minute
    error_message = "Use an integer from 1 to 10 for this bounded demonstration."
  }
}
