variable "vpc_cidr_block" {
  description = "VPC CIDR"
  type        = string
  default     = "10.32.0.0/16"
}

variable "vpc_name" {
  description = "VPC name"
  type        = string
  default     = "terraform-book-vpc"
}

variable "availability_zones" {
  description = "AZ list"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
}

variable "enable_ipv6" {
  description = "IPv6を有効にするか（dualstack時にtrue）"
  type        = bool
  default     = true
}

variable "asg_target_mem_percent" {
  type        = number
  description = "Auto Scaling のターゲットトラッキングで狙うメモリ使用率（％）。ASG 内インスタンスの平均 mem_used_percent を目標値に維持します。"
  default     = 50
}
