variable "aws_profile_name" {
    type = string
    default = "develop"
}

provider "aws" {
  profile = var.aws_profile_name
}

# 現在のAWSアカウント情報を取得
data "aws_caller_identity" "current" {}

# 現在のリージョンを取得
data "aws_region" "current" {}

output "account_id" {
  value       = data.aws_caller_identity.current.account_id
}

output "current_region" {
  value       = data.aws_region.current.name
}