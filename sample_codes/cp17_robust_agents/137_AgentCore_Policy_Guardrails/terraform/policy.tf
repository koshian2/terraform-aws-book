resource "aws_bedrockagentcore_policy_engine" "inquiry" {
  name        = "${var.name}_engine"
  description = "Reject prompt attacks and suppress passwords in runbook results"
}

resource "aws_iam_role_policy" "policy" {
  name = "evaluate_inquiry_policy"
  role = aws_iam_role.gateway.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:GetPolicyEngine"]
        Resource = aws_bedrockagentcore_policy_engine.inquiry.policy_engine_arn
      },
      {
        Effect = "Allow"
        Action = ["bedrock-agentcore:AuthorizeAction", "bedrock-agentcore:PartiallyAuthorizeActions"]
        Resource = [
          aws_bedrockagentcore_policy_engine.inquiry.policy_engine_arn,
          "${local.runtime_prefix}:gateway/${local.gateway_name}-*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeGuardrailChecks"]
        Resource = "*"
      }
    ]
  })
}

# The AWS provider exposes Cedar only. CloudFormation supports Definition.Policy,
# which is required for the guardrails extension. No custom resource or Lambda.
resource "aws_cloudformation_stack" "policies" {
  name = "${local.gateway_name}-policies"
  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Resources = {
      AllowRunbook = {
        DependsOn = ["RejectPromptAttack", "SuppressPassword"]
        Type      = "AWS::BedrockAgentCore::Policy"
        Properties = {
          Name            = "allow_runbook"
          PolicyEngineId  = aws_bedrockagentcore_policy_engine.inquiry.policy_engine_id
          EnforcementMode = "ACTIVE"
          ValidationMode  = "IGNORE_ALL_FINDINGS"
          Definition = { Cedar = { Statement = <<-CEDAR
            permit (
              principal,
              action == AgentCore::Action::"${local.target_name}___get_runbook",
              resource == AgentCore::Gateway::"${aws_bedrockagentcore_gateway.inquiry.gateway_arn}"
            );
          CEDAR
          } }
        }
      }
      SuppressPassword = {
        Type = "AWS::BedrockAgentCore::Policy"
        Properties = {
          Name            = "suppress_password"
          PolicyEngineId  = aws_bedrockagentcore_policy_engine.inquiry.policy_engine_id
          EnforcementMode = "ACTIVE"
          ValidationMode  = "IGNORE_ALL_FINDINGS"
          Definition = { Policy = { Statement = <<-POLICY
            suppressOutput (
              principal,
              action == AgentCore::Action::"${local.target_name}___get_runbook",
              resource == AgentCore::Gateway::"${aws_bedrockagentcore_gateway.inquiry.gateway_arn}"
            ) when guardrails {
              BedrockGuardrails::SensitiveInformation(["PASSWORD"], ["$.result.content[*].text", "$.result.structuredContent.text"]).maxConfidenceScore().greaterThan(decimal("0.2"))
            };
          POLICY
          } }
        }
      }
      RejectPromptAttack = {
        Type = "AWS::BedrockAgentCore::Policy"
        Properties = {
          Name            = "reject_prompt_attack"
          PolicyEngineId  = aws_bedrockagentcore_policy_engine.inquiry.policy_engine_id
          EnforcementMode = "ACTIVE"
          ValidationMode  = "IGNORE_ALL_FINDINGS"
          Definition = { Policy = { Statement = <<-POLICY
            forbid (
              principal,
              action == AgentCore::Action::"${local.target_name}___get_runbook",
              resource == AgentCore::Gateway::"${aws_bedrockagentcore_gateway.inquiry.gateway_arn}"
            ) when guardrails {
              BedrockGuardrails::PromptAttack(["PROMPT_INJECTION", "JAILBREAK", "PROMPT_LEAKAGE"], [context.input.text]).maxConfidenceScore().greaterThan(decimal("0.4"))
            };
          POLICY
          } }
        }
      }
    }
    Outputs = {
      RejectPolicyId = { Value = { "Fn::GetAtt" = ["RejectPromptAttack", "PolicyId"] } }
    }
  })
  # ターゲットの入力スキーマ登録後にPolicyを作成する。
  depends_on = [aws_bedrockagentcore_gateway_target.inquiry]
}

output "policy_engine_id" {
  value = aws_bedrockagentcore_policy_engine.inquiry.policy_engine_id
}
