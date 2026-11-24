output "client_config" {
  value = {
    aws_profile   = var.aws_profile
    aws_region    = var.aws_region
    runtime_id    = aws_bedrockagentcore_agent_runtime.demo.agent_runtime_id
    runtime_arn   = aws_bedrockagentcore_agent_runtime.demo.agent_runtime_arn
    runtime_log   = local.runtime_log
    evaluation_id = aws_bedrockagentcore_online_evaluation_config.demo.online_evaluation_config_id
    service_name  = "${var.name}.DEFAULT"
  }
}
