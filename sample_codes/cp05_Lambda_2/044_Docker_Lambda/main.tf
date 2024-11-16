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
  default = "lambda_opencv_oilpainting"
}

provider "aws" {
  profile = var.aws_profile_name
}
