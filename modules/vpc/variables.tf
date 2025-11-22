variable "vpc_cidr_block" {
  description = "VPC CIDR"
  type        = string
}

variable "vpc_name" {
  description = "VPC name (tags, resource namesに使用)"
  type        = string
}

variable "availability_zones" {
  description = "AZ list (public/privateをAZ数ぶん作成)"
  type        = list(string)
}

variable "assign_ipv6" {
  description = "VPCへIPv6 CIDRを割り当てるか"
  type        = bool
  default     = true
}

variable "enable_nat" {
  description = "NAT(IPv4向け)を有効化するか（fck-natを使用）"
  type        = bool
  default     = true
}

variable "nat_instance_type" {
  description = "fck-nat の EC2 インスタンスタイプ (例: t4g.nano, t4g.micro, t3.micro, c7g.medium)"
  type        = string
  default     = "t4g.micro"
}

variable "nat_ami_id" {
  description = "任意: fck-nat AMI ID（x86_64 などアーキを変えたい場合に指定）"
  type        = string
  default     = null
}

variable "nat_ha_mode" {
  description = "fck-natのHAモード"
  type        = bool
  default     = false
}

variable "nat_eip_allocation_ids" {
  description = "fck-natで利用する既存EIPのAllocation ID（任意）"
  type        = list(string)
  default     = []
}

variable "nat_use_cloudwatch_agent" {
  description = "fck-natでCloudWatch Agentを有効にするか"
  type        = bool
  default     = false
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}
