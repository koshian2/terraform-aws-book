# ECR リポジトリのデータ取得
data "aws_ecr_repository" "app_repo" {
  name = var.ecr_repository_name
}

# App Runner が ECR にアクセスするためのデプロイ用の IAM ロール作成
resource "aws_iam_role" "apprunner_deploy_role" {
  name = "${var.app_service_name}DeployRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "build.apprunner.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# App Runner のデプロイに必要なポリシーのアタッチ
resource "aws_iam_role_policy" "apprunner_deploy_policy" {
  role = aws_iam_role.apprunner_deploy_role.name
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ],
        Resource = data.aws_ecr_repository.app_repo.arn
      },
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# AppRunnerのプログラム上で動かすためのインスタンスロール
resource "aws_iam_role" "apprunner_instance_role" {
  name = "${var.app_service_name}InstanceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "tasks.apprunner.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# AppRunnerのインスタンスに必要なポリシー
resource "aws_iam_role_policy" "apprunner_instance_policy" {
  role = aws_iam_role.apprunner_instance_role.name
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
        ],
        Resource = data.aws_ssm_parameter.apprunner_password.arn
      }
    ]
  })
}

# パスワードのパラメーターストア
data "aws_ssm_parameter" "apprunner_password" {
  name = "/apprunner/login_password"
}

# AppRunnerのイメージのURIを取得
data "aws_ecr_image" "app_image" {
  repository_name = var.ecr_repository_name
  image_tag       = var.ecr_docker_image_tag
}

# App Runner サービスの作成
resource "aws_apprunner_service" "app_service" {
  service_name = var.app_service_name

  source_configuration {
    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_deploy_role.arn

    }

    image_repository {
      image_identifier      = data.aws_ecr_image.app_image.image_uri
      image_repository_type = "ECR"

      image_configuration {
        port = var.app_port
        runtime_environment_variables = {
          USERNAME = "terraform_aws" # 環境変数の指定
        }
        runtime_environment_secrets = {
          PASSWORD = data.aws_ssm_parameter.apprunner_password.arn # ARN指定も可能
        }
      }
    }
  }

  instance_configuration {
    cpu               = var.cpu
    memory            = var.memory
    instance_role_arn = aws_iam_role.apprunner_instance_role.arn
  }
}

# デプロイされた App Runner サービスの URL
output "apprunner_service_url" {
  value = aws_apprunner_service.app_service.service_url
}