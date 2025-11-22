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

variable "hosted_zone_name" {
  description = "Public hosted zone (e.g. example.com.)"
  type        = string
}

variable "viewer_domain_name" {
  description = "CloudFront で配信する独自ドメイン (e.g. app.example.com)"
  type        = string
}

variable "origin_subdomain" {
  description = "ALB 用のオリジン FQDN のサブドメイン (e.g. origin)"
  type        = string
  default     = "origin"
}
