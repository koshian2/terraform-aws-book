locals {
  gateway_name = replace(var.name, "_", "-")
  target_name  = "tenant-runtime"
}

resource "aws_iam_role" "gateway" {
  name_prefix = "${var.name}_gateway-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "bedrock-agentcore.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "${local.prefix}:gateway/*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "gateway" {
  name = "invoke_demo_runtime"
  role = aws_iam_role.gateway.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["bedrock-agentcore:InvokeAgentRuntime"]
      Resource = [
        aws_bedrockagentcore_agent_runtime.demo.agent_runtime_arn,
        "${aws_bedrockagentcore_agent_runtime.demo.agent_runtime_arn}/runtime-endpoint/*"
      ]
    }]
  })
}

resource "aws_bedrockagentcore_gateway" "demo" {
  name            = local.gateway_name
  role_arn        = aws_iam_role.gateway.arn
  authorizer_type = "CUSTOM_JWT"
  protocol_type   = "MCP"
  interceptor_configuration {
    interception_points = ["REQUEST"]
    interceptor {
      lambda { arn = aws_lambda_function.context.arn }
    }
    input_configuration { pass_request_headers = true }
  }
  depends_on = [aws_iam_role_policy.invoke_interceptor]
  authorizer_configuration {
    custom_jwt_authorizer {
      discovery_url   = "${local.issuer}/.well-known/openid-configuration"
      allowed_clients = [aws_cognito_user_pool_client.local.id]
      allowed_scopes  = [local.invoke_scope]
    }
  }
}

# Explicit deny also prevents direct invocation by other IAM principals.
resource "aws_bedrockagentcore_resource_policy" "runtime" {
  resource_arn = aws_bedrockagentcore_agent_runtime.demo.agent_runtime_arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInvocationOutsideGatewayRole"
      Effect    = "Deny"
      Principal = "*"
      Action    = ["bedrock-agentcore:InvokeAgentRuntime"]
      Resource  = aws_bedrockagentcore_agent_runtime.demo.agent_runtime_arn
      Condition = { ArnNotEquals = { "aws:PrincipalArn" = aws_iam_role.gateway.arn } }
    }]
  })
}

resource "aws_bedrockagentcore_gateway_target" "demo" {
  name               = local.target_name
  gateway_identifier = aws_bedrockagentcore_gateway.demo.gateway_id
  credential_provider_configuration {
    gateway_iam_role {
      service = "bedrock-agentcore"
      region  = var.aws_region
    }
  }
  metadata_configuration {
    allowed_request_headers = [local.tenant_header]
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

# 認可設定の反映を待ってから、接続先のツール一覧を取得する。
resource "time_sleep" "gateway_permissions" {
  create_duration = "60s"
  triggers = {
    gateway_id         = aws_bedrockagentcore_gateway.demo.gateway_id
    gateway_trust      = sha256(aws_iam_role.gateway.assume_role_policy)
    invoke_policy      = sha256(aws_iam_role_policy.gateway.policy)
    runtime_policy     = sha256(aws_bedrockagentcore_resource_policy.runtime.policy)
    interceptor_access = sha256(aws_iam_role_policy.invoke_interceptor.policy)
  }
}
