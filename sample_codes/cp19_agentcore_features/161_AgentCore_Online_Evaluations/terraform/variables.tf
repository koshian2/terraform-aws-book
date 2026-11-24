variable "aws_profile" {
  type    = string
  default = "develop"
}
variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}
variable "name" {
  type    = string
  default = "stationery_evaluation"
}
variable "model_id" {
  type    = string
  default = "jp.anthropic.claude-sonnet-4-6"
}
variable "evaluation_enabled" {
  type    = bool
  default = true
}
