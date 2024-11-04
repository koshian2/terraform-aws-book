# S3バケット名を入力
variable "s3_input_bucket_name" {
  type = string # terraform.tfvarsで規定
}

variable "s3_output_bucket_name" {
  type = string # terraform.tfvarsで規定
}

# S3バケットの作成
resource "aws_s3_bucket" "input_bucket" {
  bucket        = var.s3_input_bucket_name
  force_destroy = true # 開発用
}

resource "aws_s3_bucket" "output_bucket" {
  bucket        = var.s3_output_bucket_name
  force_destroy = true # 開発用
}

# デプロイしたLambda関数をS3から実行することを許可する
resource "aws_lambda_permission" "allow_s3_to_invoke_lambda" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_trigger_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input_bucket.arn
}

# S3バケット通知の設定
resource "aws_s3_bucket_notification" "s3_notification" {
  bucket = aws_s3_bucket.input_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_trigger_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix = ".json"
  }

  depends_on = [aws_lambda_permission.allow_s3_to_invoke_lambda]
}