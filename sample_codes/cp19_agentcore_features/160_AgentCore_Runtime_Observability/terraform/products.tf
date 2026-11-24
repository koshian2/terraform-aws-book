resource "aws_dynamodb_table" "products" {
  name         = "${local.gateway_name}-products"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "product_id"
  attribute {
    name = "product_id"
    type = "S"
  }
}

resource "aws_dynamodb_table_item" "products" {
  for_each = {
    P001 = { name = "ノート", price = 300 }
    P002 = { name = "ペン", price = 150 }
  }
  table_name = aws_dynamodb_table.products.name
  hash_key   = aws_dynamodb_table.products.hash_key
  item = jsonencode({
    product_id = { S = each.key }
    name       = { S = each.value.name }
    unit_price = { N = tostring(each.value.price) }
  })
}
