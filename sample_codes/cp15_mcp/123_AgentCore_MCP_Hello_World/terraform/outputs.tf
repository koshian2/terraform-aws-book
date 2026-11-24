output "runtime_arn" {
  value = aws_bedrockagentcore_agent_runtime.hello.agent_runtime_arn
}

output "connection" {
  description = "ローカルクライアントとHTTP中継が読み取る接続情報。"
  value = {
    profile = var.aws_profile
    region  = var.aws_region
    url     = "https://bedrock-agentcore.${var.aws_region}.${data.aws_partition.current.dns_suffix}/runtimes/${urlencode(aws_bedrockagentcore_agent_runtime.hello.agent_runtime_arn)}/invocations?qualifier=DEFAULT"
  }
}

output "invoke_policy_json" {
  description = "呼び出し元に付与するポリシーの例。出力だけでは権限は付与されません。"
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "bedrock-agentcore:InvokeAgentRuntime"
      Resource = [aws_bedrockagentcore_agent_runtime.hello.agent_runtime_arn, "${aws_bedrockagentcore_agent_runtime.hello.agent_runtime_arn}/runtime-endpoint/DEFAULT"]
    }]
  })
}
