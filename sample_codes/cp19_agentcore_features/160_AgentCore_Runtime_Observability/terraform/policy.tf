resource "aws_bedrockagentcore_policy_engine" "demo" {
  name        = "${var.name}_engine"
  description = "Observe quantity authorization and downstream quote execution"
}

resource "aws_iam_role_policy" "policy" {
  name = "evaluate_quote_policy"
  role = aws_iam_role.gateway.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock-agentcore:GetPolicyEngine", "bedrock-agentcore:AuthorizeAction", "bedrock-agentcore:PartiallyAuthorizeActions"]
      Resource = [aws_bedrockagentcore_policy_engine.demo.policy_engine_arn, "${local.prefix}:gateway/${local.gateway_name}-*"]
    }]
  })
}

resource "aws_bedrockagentcore_policy" "allow" {
  # Broad permit + specific forbid are intentional. Static permissiveness
  # findings must not block this teaching example; verify both decisions live.
  name             = "allow_quote"
  policy_engine_id = aws_bedrockagentcore_policy_engine.demo.policy_engine_id
  validation_mode  = "IGNORE_ALL_FINDINGS"
  definition {
    cedar {
      statement = <<-CEDAR
        permit (
          principal,
          action == AgentCore::Action::"${local.target_name}___calculate_quote",
          resource == AgentCore::Gateway::"${aws_bedrockagentcore_gateway.demo.gateway_arn}"
        );
      CEDAR
    }
  }
  depends_on = [aws_bedrockagentcore_gateway_target.demo]
}

resource "aws_bedrockagentcore_policy" "deny" {
  name             = "deny_large_quantity"
  policy_engine_id = aws_bedrockagentcore_policy_engine.demo.policy_engine_id
  validation_mode  = "IGNORE_ALL_FINDINGS"
  definition {
    cedar {
      statement = <<-CEDAR
        forbid (
          principal,
          action == AgentCore::Action::"${local.target_name}___calculate_quote",
          resource == AgentCore::Gateway::"${aws_bedrockagentcore_gateway.demo.gateway_arn}"
        ) when { context.input.quantity > 100 };
      CEDAR
    }
  }
  depends_on = [aws_bedrockagentcore_gateway_target.demo]
}
