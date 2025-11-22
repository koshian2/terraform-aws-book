variable "vpc_cidr_block" {
  description = "VPCのCIDRブロック"
  type        = string
  default     = "10.32.0.0/16"
}

variable "vpc_name" {
  description = "VPCの名前"
  type        = string
  default     = "terraform-book-vpc"
}

variable "my_ip" {
  description = "あなたのグローバルIPv4（CIDRなし、例: 203.0.113.10）"
  type        = string

  # 入力チェック（有効なIPv4かを /32 を付けて検証）
  validation {
    condition     = can(cidrhost("${var.my_ip}/32", 0))
    error_message = "有効なIPv4アドレスを指定してください（例: 203.0.113.10）。"
  }
}

variable "app_name" {
  type    = string
  default = "Demo Web"
}