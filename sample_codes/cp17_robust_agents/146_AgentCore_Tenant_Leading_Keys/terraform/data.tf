locals {
  tenant_header = "X-Amzn-Bedrock-AgentCore-Runtime-Custom-Tenant-Id"
  tenants = {
    tenant-a = "商品が届きません。"
    tenant-b = "請求書の宛名を変更してください。"
  }
  # An absent, unknown or additional session tag is not accepted.
  session_conditions = {
    StringEquals                = { "aws:RequestTag/TenantId" = keys(local.tenants) }
    "ForAllValues:StringEquals" = { "aws:TagKeys" = ["TenantId"] }
    Null                        = { "aws:RequestTag/TenantId" = "false" }
  }
}

resource "aws_dynamodb_table" "inquiries" {
  name         = "${var.name}-inquiries"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "tenant_id"
  range_key    = "ticket_id"
  attribute {
    name = "tenant_id"
    type = "S"
  }
  attribute {
    name = "ticket_id"
    type = "S"
  }
}

resource "aws_dynamodb_table_item" "demo" {
  for_each   = local.tenants
  table_name = aws_dynamodb_table.inquiries.name
  hash_key   = "tenant_id"
  range_key  = "ticket_id"
  item       = jsonencode({ tenant_id = { S = each.key }, ticket_id = { S = "T001" }, text = { S = each.value } })
}

resource "aws_iam_role" "reader" {
  name_prefix = "${var.name}-reader-"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Action = ["sts:AssumeRole", "sts:TagSession"],
    Principal = { AWS = aws_iam_role.runtime.arn }, Condition = local.session_conditions
  }] })
}

resource "aws_iam_role_policy" "reader" {
  name = "read_matching_partition_key"
  role = aws_iam_role.reader.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = ["dynamodb:GetItem"], Resource = aws_dynamodb_table.inquiries.arn
    Condition = {
      "ForAllValues:StringEquals" = { "dynamodb:LeadingKeys" = ["$${aws:PrincipalTag/TenantId}"] }
      Null                        = { "aws:PrincipalTag/TenantId" = "false", "dynamodb:LeadingKeys" = "false" }
    }
  }] })
}

output "table_name" { value = aws_dynamodb_table.inquiries.name }
output "allowed_tenants" { value = keys(local.tenants) }
output "reader_role_arn" { value = aws_iam_role.reader.arn }
output "runtime_role_arn" { value = aws_iam_role.runtime.arn }
