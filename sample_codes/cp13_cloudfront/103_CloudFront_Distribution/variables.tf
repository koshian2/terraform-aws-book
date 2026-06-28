#---------------------------------------
# 入力 / Inputs
#---------------------------------------
variable "aws_region" {
  description = "デプロイ先リージョン（S3 バケットはグローバル一意名が必要） / Deployment Region. S3 bucket names must be globally unique."
  type        = string
  default     = "ap-northeast-1"
}

variable "bucket_name_prefix" {
  description = "S3 バケット名プレフィックス（後ろにランダムサフィックス付与） / S3 bucket name prefix. A random suffix is added."
  type        = string
  default     = "aws-conf-page-empty"
}