# 信頼関係の定義
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# ロールを作成
resource "aws_iam_role" "lambda_role" {
  name               = "LambdaBasicRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# AWSLambdaBasicExecutionRoleマネージドポリシーを追加
resource "aws_iam_role_policy_attachment" "managed_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambdaの作成
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = ".cache/lambda_function.zip"
}

resource "aws_lambda_function" "api" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "hello_world_api_lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.13"
  source_code_hash = data.archive_file.lambda.output_base64sha256
}