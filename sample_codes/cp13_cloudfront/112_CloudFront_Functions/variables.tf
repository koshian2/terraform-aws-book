#---------------------------------------
# 入力
#---------------------------------------
variable "aws_region" {
  description = "デプロイ先リージョン（S3 バケットはグローバル一意名が必要）"
  type        = string
  default     = "ap-northeast-1"
}

variable "site_dir" {
  description = "静的サイトの元ディレクトリ"
  type        = string
  default     = "../../apps/aws_conference_page"
}

variable "bucket_name_prefix" {
  description = "S3 バケット名プレフィックス（後ろにランダムサフィックス付与）"
  type        = string
  default     = "aws-conf-page"
}

variable "basic_auth_username" {
  description = "Username for CloudFront basic authentication"
  type        = string
}

variable "basic_auth_password" {
  description = "Password for CloudFront basic authentication"
  type        = string
}
