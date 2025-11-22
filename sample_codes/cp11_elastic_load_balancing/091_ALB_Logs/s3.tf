# ---- ALBログ出力用 S3 バケット ----
resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "alb_logs" {
  bucket        = lower("${var.vpc_name}-alb-logs-${random_string.suffix.result}")
  force_destroy = true
  tags = {
    Name = "${var.vpc_name}-alb-logs"
  }
}

# 所有権コントロール（ログ配信のACLを受け入れるため）
resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# バケットポリシー: ALBログ配信サービスに PutObject を許可
data "aws_iam_policy_document" "alb_logs" {
  statement {
    sid    = "AllowELBLogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }

    actions = ["s3:PutObject"]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.alb_logs.id}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
    ]

    # バケット所有者が確実に所有できるよう ACL ヘッダを要求
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket     = aws_s3_bucket.alb_logs.id
  policy     = data.aws_iam_policy_document.alb_logs.json
  depends_on = [aws_s3_bucket_ownership_controls.alb_logs]
}

# ライフサイクル（90日で削除）
resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-alb-logs-after-90-days"
    status = "Enabled"

    filter {
      prefix = "alb/" # aws_lb.access_logs.prefix と合わせる
    }

    expiration {
      days = 90
    }
  }
}