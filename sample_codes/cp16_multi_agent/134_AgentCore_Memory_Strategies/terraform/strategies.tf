resource "aws_bedrockagentcore_memory_strategy" "semantic" {
  name                = "travel_facts"
  memory_id           = aws_bedrockagentcore_memory.demo.id
  type                = "SEMANTIC"
  namespace_templates = ["/facts/{actorId}/"]
}

# Serialize updates to the same Memory, including during destroy.
resource "aws_bedrockagentcore_memory_strategy" "preference" {
  name                = "travel_preferences"
  memory_id           = aws_bedrockagentcore_memory.demo.id
  type                = "USER_PREFERENCE"
  namespace_templates = ["/preferences/{actorId}/"]
  depends_on          = [aws_bedrockagentcore_memory_strategy.semantic]
}

resource "aws_bedrockagentcore_memory_strategy" "summary" {
  name                = "travel_summary"
  memory_id           = aws_bedrockagentcore_memory.demo.id
  type                = "SUMMARIZATION"
  namespace_templates = ["/summaries/{actorId}/{sessionId}/"]
  depends_on          = [aws_bedrockagentcore_memory_strategy.preference]
}

resource "aws_bedrockagentcore_memory_strategy" "episodic" {
  name                = "travel_episodes"
  memory_id           = aws_bedrockagentcore_memory.demo.id
  type                = "EPISODIC"
  namespace_templates = ["/episodes/{actorId}/{sessionId}/"]
  reflection_configuration {
    namespace_templates = ["/episodes/{actorId}/"]
  }
  depends_on = [aws_bedrockagentcore_memory_strategy.summary]
}

output "client_config" {
  value = {
    aws_profile = var.aws_profile
    aws_region  = var.aws_region
    memory_id   = aws_bedrockagentcore_memory.demo.id
    strategies = {
      episodic = {
        id        = aws_bedrockagentcore_memory_strategy.episodic.memory_strategy_id
        type      = "EPISODIC"
        namespace = one(aws_bedrockagentcore_memory_strategy.episodic.namespace_templates)
      }
      semantic = {
        id        = aws_bedrockagentcore_memory_strategy.semantic.memory_strategy_id
        type      = "SEMANTIC"
        namespace = one(aws_bedrockagentcore_memory_strategy.semantic.namespace_templates)
      }
      preference = {
        id        = aws_bedrockagentcore_memory_strategy.preference.memory_strategy_id
        type      = "USER_PREFERENCE"
        namespace = one(aws_bedrockagentcore_memory_strategy.preference.namespace_templates)
      }
      summary = {
        id        = aws_bedrockagentcore_memory_strategy.summary.memory_strategy_id
        type      = "SUMMARIZATION"
        namespace = one(aws_bedrockagentcore_memory_strategy.summary.namespace_templates)
      }
    }
  }
}
