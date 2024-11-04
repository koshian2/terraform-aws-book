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

# S3にから読み取りできるポリシーの作成と登録。インラインポリシーで定義
resource "aws_iam_role_policy" "s3_write_policy" {
  name = "LambdaS3WritePolicy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Effect = "Allow",
        Resource = [
          "${aws_s3_bucket.example_bucket.arn}",
          "${aws_s3_bucket.example_bucket.arn}/*"
        ]
      }
    ]
  })
}

# AWSLambdaBasicExecutionRoleマネージドポリシー
resource "aws_iam_role_policy_attachment" "managed_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# LambdaのZip
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = ".cache/lambda_function.zip"
}

# Lambdaの作成
resource "aws_lambda_function" "s3_trigger_lambda" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "s3_trigger_lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 30
}