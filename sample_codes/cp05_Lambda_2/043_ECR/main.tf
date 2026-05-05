terraform {
  backend "local" {
    path = ".cache/terraform.tfstate"
  }
}

provider "aws" {
  profile = var.aws_profile_name
}

variable "aws_profile_name" {
  type    = string
  default = "develop"
}

variable "ecr_repository_name" {
  type    = string
  default = "terraform-aws-book"
}


# ECRリポジトリの作成 / Create ECR repository
resource "aws_ecr_repository" "terraform_aws_book" {
  name = var.ecr_repository_name

  # イメージスキャンの設定：Push時にスキャニングする / Image scan settings: scan on push
  image_scanning_configuration {
    scan_on_push = true
  }

  lifecycle {
    prevent_destroy = true # 破棄されないようにする / Prevent destruction

  }
}

# ライフサイクルポリシーの設定（オプション） / Configure lifecycle policy (optional)
resource "aws_ecr_lifecycle_policy" "terraform_aws_book" {
  repository = aws_ecr_repository.terraform_aws_book.name

  # タグのついていないイメージを30日経過後に削除する / Delete untagged images after 30 days
  policy = jsonencode({
    "rules" = [
      {
        "rulePriority" = 1,
        "description"  = "Expire untagged images older than 30 days",
        "selection" = {
          "tagStatus"   = "untagged",
          "countType"   = "sinceImagePushed",
          "countUnit"   = "days",
          "countNumber" = 30
        },
        "action" = {
          "type" = "expire"
        }
      }
    ]
  })

  lifecycle {
    prevent_destroy = true # 破棄されないようにする / Prevent destruction
  }
}