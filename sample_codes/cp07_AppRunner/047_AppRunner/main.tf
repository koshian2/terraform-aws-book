terraform {
  backend "local" {
    path = ".cache/terraform.tfstate"
  }
}

variable "aws_profile_name" {
  type    = string
  default = "develop"
}

variable "ecr_repository_name" {
  type    = string
  default = "terraform-aws-book"
}

variable "ecr_docker_image_tag" {
  type    = string
  default = "apprunner_gradio"
}

# App Runner サービスの名前
variable "app_service_name" {
  type    = string
  default = "GradioImageClassificationApp"
}

# リッスンするポート
variable "app_port" {
  type    = string
  default = "8080"
}

# App Runner インスタンスのCPU
variable "cpu" {
  type    = string
  default = "512" # 0.5 vCPU
}

# App Runner インスタンスのメモリ (MB)
variable "memory" {
  type    = string
  default = "1024" # 1 GB
}

provider "aws" {
  profile = var.aws_profile_name
}
