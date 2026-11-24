resource "aws_bedrockagentcore_policy_engine" "inquiry" {
  name        = "${var.name}_engine"
  description = "Read before close, same user, ticket and policy session within five minutes"
}

resource "aws_iam_role_policy" "policy" {
  role = aws_iam_role.gateway.id
  name = "evaluate_temporal_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow", Action = ["bedrock-agentcore:GetPolicyEngine"]
        Resource = aws_bedrockagentcore_policy_engine.inquiry.policy_engine_arn
      },
      {
        Effect   = "Allow", Action = ["bedrock-agentcore:AuthorizeAction", "bedrock-agentcore:PartiallyAuthorizeActions"]
        Resource = [aws_bedrockagentcore_policy_engine.inquiry.policy_engine_arn, "${local.runtime_prefix}:gateway/${local.gateway_name}-*"]
      },
      {
        Effect = "Allow", Action = ["bedrock-agentcore:GetWorkloadAccessToken"]
        Resource = [
          "${local.runtime_prefix}:workload-identity-directory/default",
          "${local.runtime_prefix}:workload-identity-directory/default/workload-identity/${local.gateway_name}-*"
        ]
      }
    ]
  })
}

resource "aws_bedrockagentcore_policy" "read" {
  name             = "allow_read"
  policy_engine_id = aws_bedrockagentcore_policy_engine.inquiry.policy_engine_id
  definition {
    cedar {
      statement = <<-CEDAR
        permit (
          principal,
          action == AgentCore::Action::"${local.target_name}___get_inquiry",
          resource == AgentCore::Gateway::"${aws_bedrockagentcore_gateway.inquiry.gateway_arn}"
        ) when {
          principal.hasTag("username") &&
          [${jsonencode(var.reader_username)}, ${jsonencode(var.operator_username)}].contains(principal.getTag("username"))
        };
      CEDAR
    }
  }
  depends_on = [aws_bedrockagentcore_gateway_target.inquiry]
}

# A separate forbid avoids treating two permits as an AND condition.
resource "aws_bedrockagentcore_policy" "close_identity" {
  name             = "forbid_close_non_operator"
  policy_engine_id = aws_bedrockagentcore_policy_engine.inquiry.policy_engine_id
  # The temporal permit is created next; deny-by-default is intentional here.
  validation_mode = "IGNORE_ALL_FINDINGS"
  definition {
    cedar {
      statement = <<-CEDAR
        forbid (
          principal,
          action == AgentCore::Action::"${local.target_name}___close_inquiry",
          resource == AgentCore::Gateway::"${aws_bedrockagentcore_gateway.inquiry.gateway_arn}"
        ) unless {
          principal.hasTag("username") && principal.getTag("username") == ${jsonencode(var.operator_username)}
        };
      CEDAR
    }
  }
  depends_on = [aws_bedrockagentcore_gateway_target.inquiry]
}

# Provider 6.66.0 exposes only definition.cedar. Dogwood requires Definition.Policy.
resource "aws_cloudformation_stack" "temporal" {
  name = "${local.gateway_name}-temporal"
  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Resources = {
      CloseAfterRead = {
        Type = "AWS::BedrockAgentCore::Policy"
        Properties = {
          Name            = "close_after_read"
          PolicyEngineId  = aws_bedrockagentcore_policy_engine.inquiry.policy_engine_id
          EnforcementMode = "ACTIVE"
          ValidationMode  = "FAIL_ON_ANY_FINDINGS"
          Definition = { Policy = { Statement = <<-DOGWOOD
            permit (
              principal,
              action == AgentCore::Action::"${local.target_name}___close_inquiry",
              resource == AgentCore::Gateway::"${aws_bedrockagentcore_gateway.inquiry.gateway_arn}"
            ) when temporal {
              formerly within 5m AgentCore::Action::"${local.target_name}___get_inquiry"::response{
                eventResource: resource,
                eventPrincipal: principal,
                input.ticket_id: context.input.ticket_id
              }
            };
          DOGWOOD
          } }
        }
      }
    }
  })
  depends_on = [aws_bedrockagentcore_policy.read, aws_bedrockagentcore_policy.close_identity]
}

output "policy_engine_id" {
  value = aws_bedrockagentcore_policy_engine.inquiry.policy_engine_id
}
