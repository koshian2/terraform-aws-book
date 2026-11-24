output "client_config" {
  value = {
    aws_profile       = var.aws_profile
    aws_region        = var.aws_region
    account_id        = data.aws_caller_identity.current.account_id
    model_id          = var.model_id
    actor_id          = var.actor_id
    runtime_arn       = aws_bedrockagentcore_agent_runtime.cooking.agent_runtime_arn
    runtime_ids       = { cooking = aws_bedrockagentcore_agent_runtime.cooking.agent_runtime_id }
    memory_id         = aws_bedrockagentcore_memory.conversation.id
    knowledge_base_id = aws_bedrockagent_knowledge_base.recipes.id
    data_source_id    = aws_bedrockagent_data_source.recipes.data_source_id
    code_bucket       = aws_s3_bucket.code.id
    document_bucket   = aws_s3_bucket.documents.id
    vector_bucket     = aws_s3vectors_vector_bucket.vectors.vector_bucket_name
    index_name        = aws_s3vectors_index.documents.index_name
    role_names        = [aws_iam_role.runtime.name, aws_iam_role.knowledge_base.name]
  }
}
