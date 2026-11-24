resource "aws_bedrockagentcore_policy_engine" "demo" {
  name        = "${var.name}_engine"
  description = "Observe Cedar ALLOW and DENY decisions for add"
}

resource "aws_iam_role_policy" "policy" {
  name = "evaluate_calculator_policy"
  role = aws_iam_role.gateway.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock-agentcore:GetPolicyEngine", "bedrock-agentcore:AuthorizeAction", "bedrock-agentcore:PartiallyAuthorizeActions"]
      Resource = [aws_bedrockagentcore_policy_engine.demo.policy_engine_arn, "${local.runtime_prefix}:gateway/${local.gateway_name}-*"]
    }]
  })
}

resource "aws_bedrockagentcore_policy" "allow" {
  # Broad permit + specific forbid are intentional. Static permissiveness
  # findings must not block this teaching example; verify both decisions live.
  name             = "allow_add"
  policy_engine_id = aws_bedrockagentcore_policy_engine.demo.policy_engine_id
  validation_mode  = "IGNORE_ALL_FINDINGS"
  definition {
    cedar {
      statement = <<-CEDAR
        permit (
          principal,
          action == AgentCore::Action::"${local.target_name}___add",
          resource == AgentCore::Gateway::"${aws_bedrockagentcore_gateway.calculator.gateway_arn}"
        );
      CEDAR
    }
  }
  depends_on = [aws_bedrockagentcore_gateway_target.calculator]
}

resource "aws_bedrockagentcore_policy" "deny" {
  name             = "deny_large_a"
  policy_engine_id = aws_bedrockagentcore_policy_engine.demo.policy_engine_id
  validation_mode  = "IGNORE_ALL_FINDINGS"
  definition {
    cedar {
      statement = <<-CEDAR
        forbid (
          principal,
          action == AgentCore::Action::"${local.target_name}___add",
          resource == AgentCore::Gateway::"${aws_bedrockagentcore_gateway.calculator.gateway_arn}"
        ) when { context.input.a > 100 };
      CEDAR
    }
  }
  depends_on = [aws_bedrockagentcore_gateway_target.calculator]
}
