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

variable "availability_zones" {
  description = "Availability zones to use for subnets"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
}
