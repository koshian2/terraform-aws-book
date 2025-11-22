# ---- フローログ出力用 S3 バケット ----
resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "aws_s3_bucket" "flow_logs" {
  bucket        = lower("${var.vpc_name}-vpc-flow-logs-${random_string.suffix.result}")
  force_destroy = true
  tags = {
    Name = "${var.vpc_name}-vpc-flow-logs"
  }
}

# アカウントIDやリージョン情報を取得
data "aws_caller_identity" "this" {}
data "aws_region" "this" {}
data "aws_partition" "this" {}

# VPCフローログのバケットポリシー
data "aws_iam_policy_document" "flow_logs" {
  statement {
    sid = "AWSLogDeliveryWrite"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.flow_logs.arn}/AWSLogs/${data.aws_caller_identity.this.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.this.account_id]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.this.partition}:logs:${data.aws_region.this.region}:${data.aws_caller_identity.this.account_id}:*"]
    }
  }

  statement {
    sid = "AWSLogDeliveryAclCheck"
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.flow_logs.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.this.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.this.partition}:logs:${data.aws_region.this.region}:${data.aws_caller_identity.this.account_id}:*"]
    }
  }
}

# バケットポリシーを関連付け
resource "aws_s3_bucket_policy" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

# S3ライフサイクルルール（90日で削除）
resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    id     = "expire-flow-logs-after-90-days"
    status = "Enabled"

    # Flow Logs の既定保存先だけ対象
    filter {
      prefix = "AWSLogs/${data.aws_caller_identity.this.account_id}/vpcflowlogs/"
    }

    expiration {
      days = 90
    }
  }
}
