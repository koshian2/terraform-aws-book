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
  default = "hello_world_mcp"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,39}$", var.name))
    error_message = "nameは英字で始まる40文字以内の英数字とアンダースコアにしてください。"
  }
}
