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

variable "bucket_name" {
  type = string # terraform.tfvarsで規定
}

locals {
  html_files = [
    "index.html",
    "error.html",
    "about/index.html",
    "contact/index.html"
  ]
}

# バケットの作成
resource "aws_s3_bucket" "website_bucket" {
  bucket        = var.bucket_name
  force_destroy = true # 開発用
}

# ファイルアップロード
resource "aws_s3_object" "object" {
  for_each = toset(local.html_files)

  bucket       = aws_s3_bucket.website_bucket.id
  key          = each.value
  source       = "./html/${each.value}"
  content_type = "text/html"
  source_hash  = filemd5("./html/${each.value}")
}

# Webサイトの設定
resource "aws_s3_bucket_website_configuration" "circle_site" {
  bucket = aws_s3_bucket.website_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# 公開読み取りポリシーの定義
data "aws_iam_policy_document" "public_read_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.website_bucket.arn}/*"]
  }
}

# パブリックアクセスブロックの設定を無効化
resource "aws_s3_bucket_public_access_block" "website_bucket_public_access_block" {
  bucket = aws_s3_bucket.website_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# バケットポリシーの設定
resource "aws_s3_bucket_policy" "website_bucket_policy" {
  bucket     = aws_s3_bucket.website_bucket.id
  policy     = data.aws_iam_policy_document.public_read_policy.json
  depends_on = [aws_s3_bucket_public_access_block.website_bucket_public_access_block]
}

# トップページのURLを表示
output "website_url" {
  value = "http://${aws_s3_bucket_website_configuration.circle_site.website_endpoint}"
}