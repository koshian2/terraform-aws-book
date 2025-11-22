# --- Athena用のS3バケットとワークグループだけ定義する ---
# Athena クエリ結果用バケット
resource "random_string" "athena_suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "aws_s3_bucket" "athena_results" {
  bucket        = lower("${var.vpc_name}-athena-results-${random_string.athena_suffix.result}")
  force_destroy = true
}

# Athena ワークグループ（結果出力先のみ指定）
resource "aws_athena_workgroup" "vpcflow" {
  name = "${var.vpc_name}-wg"

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/"
    }
    enforce_workgroup_configuration = true
  }

  force_destroy = true
}

# Athena データベース
resource "aws_athena_database" "network" {
  name   = "${replace(var.vpc_name, "-", "_")}_network_logs"
  bucket = aws_s3_bucket.athena_results.bucket
}
