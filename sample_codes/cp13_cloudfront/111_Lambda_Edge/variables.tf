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

variable "bucket_name_prefix" {
  description = "S3 バケット名プレフィックス（後ろにランダムサフィックス付与）"
  type        = string
  default     = "error-page"
}

variable "site_dir" {
  description = "静的サイトの元ディレクトリ"
  type        = string
  default     = "../../apps/aws_conference_page"
}