variable "vpc_cidr_block" {
  description = "VPC CIDR"
  type        = string
  default     = "10.32.0.0/16"
}

variable "vpc_name" {
  description = "VPC名 / VPC name"
  type        = string
  default     = "terraform-book-vpc"
}

variable "availability_zones" {
  description = "AZのリスト / List of Availability Zones"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
}

variable "enable_ipv6" {
  description = "IPv6を有効にするか（dualstack時にtrue） / Whether to enable IPv6. Set true for dualstack."
  type        = bool
  default     = true
}

variable "public_zone_name" {
  description = "Route 53 パブリックホストゾーン名 (e.g., example.com) / Route 53 public hosted zone name, for example example.com"
  type        = string
}
