#========================================
# Lambda@Edge 用 ZIP 作成
#========================================
data "archive_file" "lambda_edge_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_edge.py"
  output_path = "${path.module}/.cache/lambda_edge.zip"
}

#========================================
# Lambda@Edge 用 IAM ロール
#========================================
resource "aws_iam_role" "lambda_edge" {
  name = "${var.vpc_name}-lambda-edge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "edgelambda.amazonaws.com"
          ]
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_edge_basic" {
  role       = aws_iam_role.lambda_edge.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#========================================
# Lambda@Edge 関数本体（us-east-1）
#========================================
resource "aws_lambda_function" "edge_error_redirect" {
  provider = aws.us_east_1

  function_name = "${var.vpc_name}-cloudfront-edge-error-redirect"
  description   = "Origin Response Lambda@Edge to redirect error status to /error.html?type=..."

  filename         = data.archive_file.lambda_edge_zip.output_path
  source_code_hash = data.archive_file.lambda_edge_zip.output_base64sha256

  role    = aws_iam_role.lambda_edge.arn
  handler = "lambda_edge.lambda_handler" # lambda_edge.py の lambda_handler
  runtime = "python3.12"

  # Lambda@Edge はバージョン付き ARN が必要なので publish = true
  publish = true
}
