locals {
  prefix        = "cooking-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  bedrock_arn   = "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}"
  embedding_arn = "${local.bedrock_arn}::foundation-model/amazon.titan-embed-text-v2:0"
  recipes       = { for r in jsondecode(file("${path.module}/../data/recipes.json")) : r.recipe_id => r }
}

resource "aws_s3_object" "recipe" {
  for_each = local.recipes
  bucket   = aws_s3_bucket.documents.id
  key      = "documents/${each.key}.txt"
  content = join("\n", [
    "料理ID: ${each.key}", "料理名: ${each.value.name}", "区分: ${each.value.category}",
    "人数: ${each.value.servings}人", "調理時間の目安: ${each.value.minutes}分",
    "器具: ${join("、", each.value.equipment)}", "特徴: ${join("、", each.value.tags)}",
    "材料: ${join("、", each.value.ingredients)}",
    "手順:", join("\n", [for i, step in each.value.steps : "${i + 1}. ${step}"]),
    "学習用に作成した架空のレシピです。調理検証済みではありません。"
  ])
  content_type = "text/plain; charset=utf-8"
  depends_on   = [aws_s3_bucket_public_access_block.documents, aws_s3_bucket_server_side_encryption_configuration.documents]
}
resource "aws_s3_object" "metadata" {
  for_each     = local.recipes
  bucket       = aws_s3_bucket.documents.id
  key          = "documents/${each.key}.txt.metadata.json"
  content      = jsonencode({ metadataAttributes = { recipe_id = each.key, name = each.value.name, category = each.value.category } })
  content_type = "application/json"
  depends_on   = [aws_s3_bucket_public_access_block.documents, aws_s3_bucket_server_side_encryption_configuration.documents]
}
resource "aws_bedrockagent_knowledge_base" "recipes" {
  name     = "cooking-recipes"
  role_arn = aws_iam_role.knowledge_base.arn
  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = local.embedding_arn
      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions          = 1024
          embedding_data_type = "FLOAT32"
        }
      }
    }
  }
  storage_configuration {
    type = "S3_VECTORS"
    s3_vectors_configuration { index_arn = aws_s3vectors_index.documents.index_arn }
  }
  depends_on = [aws_iam_role_policy.knowledge_base]
}
resource "aws_bedrockagent_data_source" "recipes" {
  name                 = "cooking-recipes"
  knowledge_base_id    = aws_bedrockagent_knowledge_base.recipes.id
  data_deletion_policy = "DELETE"
  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = aws_s3_bucket.documents.arn
      inclusion_prefixes = ["documents/"]
    }
  }
  vector_ingestion_configuration {
    # 短いレシピを1件ずつ全文で返し、手順の途中だけが検索されることを避ける。
    chunking_configuration { chunking_strategy = "NONE" }
  }
  depends_on = [aws_s3_object.recipe, aws_s3_object.metadata]
}
