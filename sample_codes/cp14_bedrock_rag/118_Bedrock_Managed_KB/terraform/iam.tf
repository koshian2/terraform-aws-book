resource "aws_iam_role" "knowledge_base" {
  name = "managed-kb-knowledge-base-${var.aws_region}"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "bedrock.amazonaws.com" },
    Condition = {
      StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      ArnLike      = { "aws:SourceArn" = "${local.bedrock_arn}:${data.aws_caller_identity.current.account_id}:knowledge-base/*" }
    }
  }] })
}
resource "aws_iam_role_policy" "knowledge_base" {
  role = aws_iam_role.knowledge_base.id
  name = "sample-documents"
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "s3:ListBucket", Resource = aws_s3_bucket.documents.arn },
    { Effect = "Allow", Action = "s3:GetObject", Resource = "${aws_s3_bucket.documents.arn}/documents/*" }

  ] })
}
