variable "vpc_cidr_block" {
  description = "VPCのCIDRブロック / VPC CIDR block"
  type        = string
  default     = "10.32.0.0/16"
}

variable "vpc_name" {
  description = "VPCの名前 / VPC name"
  type        = string
  default     = "terraform-book-vpc"
}

variable "my_ip" {
  description = "あなたのグローバルIPv4（CIDRなし、例: 203.0.113.10） / Your global IPv4 address without CIDR, for example 203.0.113.10"
  type        = string

  # 入力チェック（有効なIPv4かを /32 を付けて検証） / Input check: add /32 and verify that it is a valid IPv4 address
  validation {
    condition     = can(cidrhost("${var.my_ip}/32", 0))
    error_message = "有効なIPv4アドレスを指定してください（例: 203.0.113.10）。 / Enter a valid IPv4 address, for example 203.0.113.10."
  }
}

variable "app_name" {
  type    = string
  default = "Demo Web"
}