resource "aws_bedrockagentcore_policy_engine" "demo" {
  name        = "${var.name}_engine"
  description = "Allow VIP users to reserve presale products"
}

resource "aws_iam_role_policy" "policy" {
  name = "evaluate_vip_policy"
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

resource "aws_bedrockagentcore_policy" "vip" {
  name             = "allow_vip_reservation"
  policy_engine_id = aws_bedrockagentcore_policy_engine.demo.policy_engine_id
  definition {
    cedar {
      statement = <<-CEDAR
        permit (
          principal is AgentCore::OAuthUser,
          action == AgentCore::Action::"${local.target_name}___reserve_product",
          resource == AgentCore::Gateway::"${aws_bedrockagentcore_gateway.presale.gateway_arn}"
        ) when {
          principal.hasTag("cognito:groups") &&
          principal.getTag("cognito:groups") like "*vip*"
        };
      CEDAR
    }
  }
  depends_on = [aws_bedrockagentcore_gateway_target.presale]
}
