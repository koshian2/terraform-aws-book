variable "web_vpc_cidr_block" {
  description = "VPC CIDR (for Web)"
  type        = string
  default     = "10.32.0.0/16"
}

variable "vpn_vpc_cidr_block" {
  description = "VPC CIDR (for VPN)"
  type        = string
  default     = "10.33.0.0/16"
}

variable "web_vpc_name" {
  description = "VPC name (for Web)"
  type        = string
  default     = "terraform-book-web-vpc"
}

variable "vpn_vpc_name" {
  description = "VPC name (for VPN)"
  type        = string
  default     = "terraform-book-vpn-vpc"
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