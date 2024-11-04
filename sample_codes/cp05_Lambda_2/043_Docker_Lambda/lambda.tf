# ロールを作成
resource "aws_iam_role" "lambda_role" {
  name = "LambdaS3ExecitonRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Lambdaのポリシー設定（S3の読み書き）
data "aws_iam_policy_document" "translate_policy" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      "${aws_s3_bucket.input_bucket.arn}",
      "${aws_s3_bucket.input_bucket.arn}/*"
    ]
  }

  statement {
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.output_bucket.arn}",
      "${aws_s3_bucket.output_bucket.arn}/*"
    ]
  }
}

# S3を読み書きするポリシー
resource "aws_iam_role_policy" "s3_write_policy" {
  name   = "LambdaS3ReadWritePolicy"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.translate_policy.json
}

# AWSLambdaBasicExecutionRoleマネージドポリシー
resource "aws_iam_role_policy_attachment" "managed_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# LambdaのイメージのURIを取得
data "aws_ecr_image" "lambda_image" {
  repository_name = var.ecr_repository_name
  image_tag       = var.ecr_docker_image_tag
}

# Lambdaの作成
resource "aws_lambda_function" "opencv_lambda" {
  function_name = "s3_trigger_opencv_lambda"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  memory_size   = 512
  timeout       = 60
  image_uri     = data.aws_ecr_image.lambda_image.image_uri

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output_bucket.id
    }
  }
}

output "docker_image_with_digest" {
  value = data.aws_ecr_image.lambda_image.image_uri
}