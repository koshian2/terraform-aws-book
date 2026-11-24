output "client_config" {
  value = {
    aws_profile       = var.aws_profile
    aws_region        = var.aws_region
    account_id        = data.aws_caller_identity.current.account_id
    knowledge_base_id = aws_bedrockagent_knowledge_base.minutes.id
    data_source_id    = aws_bedrockagent_data_source.minutes.data_source_id
    document_bucket   = aws_s3_bucket.documents.id
    vector_bucket     = aws_s3vectors_vector_bucket.vectors.vector_bucket_name
    index_name        = aws_s3vectors_index.documents.index_name
    index_arn         = aws_s3vectors_index.documents.index_arn
    role_name         = aws_iam_role.knowledge_base.name
    model_id          = var.model_id
    embedding_model   = local.embedding_arn
  }
}
