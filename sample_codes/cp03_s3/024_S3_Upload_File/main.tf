terraform {
  backend "local" {
    path = ".cache/terraform.tfstate"
  }
}

variable "aws_profile_name" {
  type    = string
  default = "develop"
}

variable "bucket_name" {
  type = string
}

provider "aws" {
  profile = var.aws_profile_name
}

resource "aws_s3_bucket" "example_bucket" {
  bucket        = var.bucket_name
  force_destroy = true
}

resource "aws_s3_object" "example_object" {
  bucket = aws_s3_bucket.example_bucket.bucket
  key    = "example/sample.txt"
  source = "./sample.txt"
  source_hash = filemd5("./sample.txt")
}