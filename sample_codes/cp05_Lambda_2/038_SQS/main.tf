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

# 標準キューの作成 / Create standard queue
resource "aws_sqs_queue" "standard_queue" {
  name                       = "my-standard-queue"
  message_retention_seconds  = 43200 # 12h
  receive_wait_time_seconds  = 0
  visibility_timeout_seconds = 30
}

# FIFOキューの作成 / Create FIFO queue
resource "aws_sqs_queue" "fifo_queue" {
  name       = "my-fifo-queue.fifo" # FIFOキュー名は .fifo で終わる必要があり / FIFO queue name must end with .fifo
  fifo_queue = true
  content_based_deduplication = true # trueにすると重複したメッセージが短時間内の重複削除がされる / When true, duplicate messages are deduplicated within a short time window
  message_retention_seconds  = 43200
  receive_wait_time_seconds  = 10 # 0より大きくするとロングポーリング / Greater than 0 enables long polling
  visibility_timeout_seconds = 30
}