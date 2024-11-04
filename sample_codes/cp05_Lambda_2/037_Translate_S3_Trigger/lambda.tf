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

# Lambdaのポリシー設定（S3の読み書き＋Translate）
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

  statement {
    actions = ["translate:TranslateText"]
    resources = ["*"]
  }
}

# S3
resource "aws_iam_role_policy" "s3_write_policy" {
  name = "LambdaS3WritePolicy"
  role = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.translate_policy.json
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
  function_name    = "s3_trigger_translate_lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 20

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output_bucket.id
    }
  }
}