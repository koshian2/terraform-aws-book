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

