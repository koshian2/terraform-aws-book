locals { target_name = "managed-kb" }
resource "aws_iam_role" "gateway" {
  name_prefix = "${var.name}-gateway-"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Action = "sts:AssumeRole", Principal = { Service = "bedrock-agentcore.amazonaws.com" },
    Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }, ArnLike = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}:gateway/*" } }
  }] })
}
resource "aws_iam_role_policy" "gateway" {
  role = aws_iam_role.gateway.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = ["bedrock:GetKnowledgeBase", "bedrock:Retrieve"], Resource = aws_bedrockagent_knowledge_base.shared.arn
  }] })
}
resource "aws_bedrockagentcore_gateway" "demo" {
  name            = replace(var.name, "_", "-")
  role_arn        = aws_iam_role.gateway.arn
  authorizer_type = "CUSTOM_JWT"
  protocol_type   = "MCP"
  authorizer_configuration {
    custom_jwt_authorizer {
      discovery_url   = "${local.issuer}/.well-known/openid-configuration"
      allowed_clients = [aws_cognito_user_pool_client.local.id]
      allowed_scopes  = [local.invoke_scope]
    }
  }
  interceptor_configuration {
    interception_points = ["REQUEST"]
    interceptor {
      lambda { arn = aws_lambda_function.context.arn }
    }
    input_configuration { pass_request_headers = true }
  }
  depends_on = [aws_iam_role_policy.invoke_interceptor, aws_lambda_permission.pre_token]
}
resource "time_sleep" "gateway_permissions" {
  create_duration = "60s"
  triggers = {
    gateway_id = aws_bedrockagentcore_gateway.demo.gateway_id
    access     = sha256(aws_iam_role_policy.gateway.policy)
    invoke     = sha256(aws_iam_role_policy.invoke_interceptor.policy)
  }
}
resource "aws_bedrockagentcore_gateway_target" "documents" {
  name               = local.target_name
  gateway_identifier = aws_bedrockagentcore_gateway.demo.gateway_id
  credential_provider_configuration {
    gateway_iam_role {}
  }
  target_configuration {
    mcp {
      connector {
        source { connector_id = "bedrock-knowledge-bases" }
        enabled = ["Retrieve"]
        configuration {
          name        = "Retrieve"
          description = "契約企業の資料を検索します。質問を指定してください。所属と閲覧者はサーバーで設定します。"
          parameter_values = jsonencode({
            knowledgeBaseId        = aws_bedrockagent_knowledge_base.shared.id,
            retrievalConfiguration = { managedSearchConfiguration = { numberOfResults = 10 } }
          })
          # Interceptorから渡す値もコネクタが受け取れるようにする。
          # モデルが値を送ってもInterceptorが必ず置換する。
          parameter_override {
            path        = "$.userContext"
            visible     = true
            description = "サーバーが認証情報から上書きします。指定不要です。"
          }
          parameter_override {
            path        = "$.retrievalConfiguration.managedSearchConfiguration.filter"
            visible     = true
            description = "サーバーが所属から上書きします。指定不要です。"
          }
        }
      }
    }
  }
  depends_on = [time_sleep.gateway_permissions]
}
