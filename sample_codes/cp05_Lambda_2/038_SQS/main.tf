terraform {
  backend "local" {
    path = ".cache/terraform.tfstate"
  }
}

variable "aws_profile_name" {
  type    = string
  default = "develop"
}

provider "aws" {
  profile = var.aws_profile_name
}

# 標準キューの作成
resource "aws_sqs_queue" "standard_queue" {
  name                       = "my-standard-queue"
  message_retention_seconds  = 43200 # 12h
  receive_wait_time_seconds  = 0
  visibility_timeout_seconds = 30
}

# FIFOキューの作成
resource "aws_sqs_queue" "fifo_queue" {
  name       = "my-fifo-queue.fifo" # FIFOキュー名は .fifo で終わる必要があり
  fifo_queue = true
  content_based_deduplication = true # trueにすると重複したメッセージが短時間内の重複削除がされる
  message_retention_seconds  = 43200
  receive_wait_time_seconds  = 10 # 0より大きくするとロングポーリング
  visibility_timeout_seconds = 30
}