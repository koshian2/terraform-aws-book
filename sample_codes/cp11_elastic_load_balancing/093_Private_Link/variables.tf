variable "vpc_a_cidr_block" {
  description = "VPC A CIDR"
  type        = string
  default     = "10.32.0.0/16"
}

variable "vpc_a_name" {
  description = "VPC A name"
  type        = string
  default     = "terraform-book-vpc-a"
}

variable "vpc_b_cidr_block" {
  description = "VPC B CIDR"
  type        = string
  default     = "10.32.0.0/16"
}

variable "vpc_b_name" {
  description = "VPC B name"
  type        = string
  default     = "terraform-book-vpc-b"
}

variable "availability_zones" {
  description = "AZ list"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
}

