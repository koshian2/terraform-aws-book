#---------------------------------------
# 入力
#---------------------------------------
variable "aws_region" {
  description = "デプロイ先リージョン（S3 バケットはグローバル一意名が必要）"
  type        = string
  default     = "ap-northeast-1"
}

variable "bucket_name_prefix" {
  description = "S3 バケット名プレフィックス（後ろにランダムサフィックス付与）"
  type        = string
  default     = "aws-conf-page-empty"
}