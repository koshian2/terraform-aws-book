locals {
  gateway_name = replace(var.name, "_", "-")
  target_name  = "inquiry-runtime"
}

resource "aws_iam_role" "gateway" {
  name_prefix = "${var.name}-gateway-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "bedrock-agentcore.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "${local.runtime_prefix}:gateway/${local.gateway_name}-*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "gateway" {
  name = "invoke_inquiry_runtime"
  role = aws_iam_role.gateway.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["bedrock-agentcore:InvokeAgentRuntime"]
      Resource = [
        aws_bedrockagentcore_agent_runtime.inquiry.agent_runtime_arn,
        "${aws_bedrockagentcore_agent_runtime.inquiry.agent_runtime_arn}/runtime-endpoint/*"
      ]
    }]
  })
}

resource "aws_bedrockagentcore_gateway" "inquiry" {
  name            = local.gateway_name
  role_arn        = aws_iam_role.gateway.arn
  authorizer_type = "CUSTOM_JWT"
  protocol_type   = "MCP"
  policy_engine_configuration {
    arn  = aws_bedrockagentcore_policy_engine.inquiry.policy_engine_arn
    mode = "ENFORCE"
  }
  authorizer_configuration {
    custom_jwt_authorizer {
      discovery_url   = "${local.issuer}/.well-known/openid-configuration"
      allowed_clients = [aws_cognito_user_pool_client.local.id]
      allowed_scopes  = [local.invoke_scope]
    }
  }
  depends_on = [aws_iam_role_policy.policy]
}

# Explicit deny also prevents direct invocation by other IAM principals.
resource "aws_bedrockagentcore_resource_policy" "runtime" {
  resource_arn = aws_bedrockagentcore_agent_runtime.inquiry.agent_runtime_arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInvocationOutsideGatewayRole"
      Effect    = "Deny"
      Principal = "*"
      Action    = ["bedrock-agentcore:InvokeAgentRuntime"]
      Resource  = aws_bedrockagentcore_agent_runtime.inquiry.agent_runtime_arn
      Condition = { ArnNotEquals = { "aws:PrincipalArn" = aws_iam_role.gateway.arn } }
    }]
  })
}

# API完了と認可への反映には時間差があるため、ツール取得の前に待機する。
# 60秒は反映完了を保証する値ではなく、初回登録時の失敗を減らすための待機。
resource "time_sleep" "gateway_permissions" {
  create_duration = "60s"
  triggers = {
    gateway_id     = aws_bedrockagentcore_gateway.inquiry.gateway_id
    gateway_trust  = sha256(aws_iam_role.gateway.assume_role_policy)
    invoke_policy  = sha256(aws_iam_role_policy.gateway.policy)
    policy_access  = sha256(aws_iam_role_policy.policy.policy)
    runtime_policy = sha256(aws_bedrockagentcore_resource_policy.runtime.policy)
  }
}

resource "aws_bedrockagentcore_gateway_target" "inquiry" {
  name               = local.target_name
  gateway_identifier = aws_bedrockagentcore_gateway.inquiry.gateway_id
  credential_provider_configuration {
    gateway_iam_role {
      service = "bedrock-agentcore"
      region  = var.aws_region
    }
  }
  target_configuration {
    mcp {
      mcp_server {
        endpoint = local.runtime_url
      }
    }
  }
  depends_on = [time_sleep.gateway_permissions]
}
