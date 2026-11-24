resource "aws_iam_role" "portal" {
  name = "${var.name}-portal"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Principal = { Service = "bedrock-agentcore.amazonaws.com" }, Action = "sts:AssumeRole",
    Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }, ArnLike = { "aws:SourceArn" = "${local.prefix}:consent-portal/${var.name}-*" } }
  }] })
}
resource "aws_iam_role_policy" "portal" {
  role = aws_iam_role.portal.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["bedrock-agentcore:GetGateway", "bedrock-agentcore:GetGatewayTarget", "bedrock-agentcore:ListGatewayTargets"], Resource = aws_bedrockagentcore_gateway.github.gateway_arn },
    { Effect = "Allow", Action = ["bedrock-agentcore:GetOauth2CredentialProvider"], Resource = [local.provider_prefix, "${local.prefix}:token-vault/default"] },
    { Effect = "Allow", Action = ["bedrock-agentcore:ListOauth2CredentialProviders"], Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } } },
    { Effect = "Allow", Action = ["bedrock-agentcore:GetWorkloadAccessTokenForJWT"], Resource = local.workload_resources },
    { Effect = "Allow", Action = ["bedrock-agentcore:CompleteResourceTokenAuth", "bedrock-agentcore:GetResourceOauth2Token"], Resource = concat([local.provider_prefix, "${local.prefix}:token-vault/default"], local.workload_resources) },
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:bedrock-agentcore-identity!default/oauth2/${var.name}-*" }
  ] })
}
resource "aws_iam_role" "manager" {
  name               = "${var.name}-manager"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_cloudwatch_log_group" "manager" {
  name              = "/aws/lambda/${var.name}-manager"
  retention_in_days = 7
}
resource "aws_iam_role_policy" "manager" {
  role = aws_iam_role.manager.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.manager.arn}:*" },
    { Effect = "Allow", Action = ["cognito-idp:CreateUserPoolClient", "cognito-idp:DescribeUserPoolClient", "cognito-idp:ListUserPoolClients", "cognito-idp:UpdateUserPoolClient", "cognito-idp:DeleteUserPoolClient"], Resource = aws_cognito_user_pool.users.arn },
    { Effect = "Allow", Action = ["bedrock-agentcore:ListConsentPortals"], Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } } },
    { Effect = "Allow", Action = ["bedrock-agentcore:GetGateway"], Resource = aws_bedrockagentcore_gateway.github.gateway_arn },
    # Provider creation checks initialization permission even for the default vault.
    { Effect = "Allow", Action = ["bedrock-agentcore:CreateTokenVault"], Resource = "${local.prefix}:token-vault/default" },
    { Effect = "Allow", Action = ["secretsmanager:CreateSecret", "secretsmanager:PutSecretValue", "secretsmanager:UpdateSecret", "secretsmanager:TagResource", "secretsmanager:DeleteSecret"], Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:bedrock-agentcore-identity!default/oauth2/${var.name}-*-oidc-*" },
    # These create APIs authorize the resource-type wildcard before an ID exists.
    { Effect = "Allow", Action = ["bedrock-agentcore:CreateOauth2CredentialProvider"], Resource = ["${local.prefix}:token-vault/default/oauth2credentialprovider/*", "${local.prefix}:token-vault/default"] },
    # Only creation uses the unscoped API permission. Existing portals remain
    # protected by the sample-name ARN restriction on get/update/delete below.
    { Effect = "Allow", Action = ["bedrock-agentcore:CreateConsentPortal"], Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } } },
    { Effect = "Allow", Action = ["bedrock-agentcore:GetConsentPortal", "bedrock-agentcore:UpdateConsentPortal", "bedrock-agentcore:DeleteConsentPortal", "bedrock-agentcore:TagResource"], Resource = "${local.prefix}:consent-portal/${var.name}-*" },
    { Effect = "Allow", Action = ["bedrock-agentcore:GetOauth2CredentialProvider", "bedrock-agentcore:UpdateOauth2CredentialProvider", "bedrock-agentcore:DeleteOauth2CredentialProvider"], Resource = [local.managed_provider_prefix, "${local.prefix}:token-vault/default"] },
    # Tagging an OAuth provider also authorizes its parent Token Vault.
    { Effect = "Allow", Action = ["bedrock-agentcore:TagResource"], Resource = [local.managed_provider_prefix, "${local.prefix}:token-vault/default"] },
    { Effect = "Allow", Action = ["iam:PassRole"], Resource = aws_iam_role.portal.arn, Condition = { StringEquals = { "iam:PassedToService" = "bedrock-agentcore.amazonaws.com" } } }
  ] })
}
resource "aws_lambda_function" "manager" {
  function_name    = "${var.name}-manager"
  role             = aws_iam_role.manager.arn
  runtime          = "python3.14"
  handler          = "portal_handler.handler"
  timeout          = 900
  memory_size      = 256
  filename         = "${path.module}/../build/portal-manager.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/portal-manager.zip")
  depends_on       = [aws_iam_role_policy.manager, aws_cloudwatch_log_group.manager]
}
resource "aws_cloudformation_stack" "portal" {
  name = "${var.name}-portal"
  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Resources = {
      Portal = {
        Type = "Custom::ConsentPortal"
        Properties = {
          ServiceToken     = aws_lambda_function.manager.arn
          ServiceTimeout   = 900
          Name             = var.name
          GatewayId        = aws_bedrockagentcore_gateway.github.gateway_id
          UserPoolId       = aws_cognito_user_pool.users.id
          Issuer           = local.issuer
          InvokeScope      = local.invoke_scope
          ExecutionRoleArn = aws_iam_role.portal.arn
          CodeVersion      = aws_lambda_function.manager.source_code_hash
        }
      }
    }
    Outputs = { for key in ["PortalId", "PortalArn", "PortalUrl", "CognitoClientId", "IdpProviderArn", "IdpProviderName"] : key => { Value = { "Fn::GetAtt" = ["Portal", key] } } }
  })
  depends_on = [aws_iam_role_policy.portal, aws_cognito_user_pool_domain.login]
  timeouts {
    create = "25m"
    update = "25m"
    delete = "25m"
  }
}
