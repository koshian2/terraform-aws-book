locals {
  tenant_header = "X-Amzn-Bedrock-AgentCore-Runtime-Custom-Tenant-Id"
  tenants = {
    tenant-a = "商品が届きません。"
    tenant-b = "請求書の宛名を変更してください。"
  }
  tenant_config = { for tenant, table in aws_dynamodb_table.inquiries : tenant => {
    table_name = table.name
    role_arn   = aws_iam_role.tenant[tenant].arn
  } }
}
resource "aws_dynamodb_table" "inquiries" {
  for_each     = local.tenants
  name         = "${var.name}-${each.key}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ticket_id"
  attribute {
    name = "ticket_id"
    type = "S"
  }
  tags = { TenantId = each.key }
}
resource "aws_dynamodb_table_item" "demo" {
  for_each   = local.tenants
  table_name = aws_dynamodb_table.inquiries[each.key].name
  hash_key   = "ticket_id"
  item       = jsonencode({ ticket_id = { S = "T001" }, text = { S = each.value } })
}
resource "aws_iam_role" "tenant" {
  for_each    = local.tenants
  name_prefix = "${var.name}-${each.key}-"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRole", Principal = { AWS = aws_iam_role.runtime.arn }
  }] })
}
resource "aws_iam_role_policy" "tenant" {
  for_each = local.tenants
  name     = "read_own_table_only"
  role     = aws_iam_role.tenant[each.key].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = ["dynamodb:GetItem"], Resource = aws_dynamodb_table.inquiries[each.key].arn
  }] })
}
output "tenant_config" { value = local.tenant_config }
output "runtime_role_arn" { value = aws_iam_role.runtime.arn }
