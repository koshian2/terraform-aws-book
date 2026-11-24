resource "aws_iam_role" "evaluation" {
  name = "${var.name}_judge"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Action = "sts:AssumeRole", Principal = { Service = "bedrock-agentcore.amazonaws.com" },
    Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }, ArnLike = { "aws:SourceArn" = "${local.prefix}:online-evaluation-config/*" } }
  }] })
}
resource "aws_cloudwatch_log_resource_policy" "spans" {
  resource_arn = "${local.logs_arn}:log-group:${local.runtime_log}"
  policy_document = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Principal = { Service = "xray.amazonaws.com" }, Action = "logs:PutLogEvents",
    Resource  = "${local.logs_arn}:log-group:${local.runtime_log}:*",
    Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }, ArnLike = { "aws:SourceArn" = "arn:aws:xray:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*" } }
  }] })
  depends_on = [terraform_data.logs]
}
resource "aws_iam_role_policy" "evaluation" {
  role = aws_iam_role.evaluation.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["logs:DescribeLogGroups", "logs:GetQueryResults"], Resource = "*" },
    { Effect = "Allow", Action = ["logs:StartQuery", "logs:DescribeIndexPolicies", "logs:PutIndexPolicy"], Resource = ["${local.logs_arn}:log-group:${local.runtime_log}", "${local.logs_arn}:log-group:${local.runtime_log}:*"] },
    { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${local.logs_arn}:log-group:/aws/bedrock-agentcore/evaluations/*" }
  ] })
}
resource "time_sleep" "evaluation_iam" {
  create_duration = "60s"
  triggers        = { policy = sha256(aws_iam_role_policy.evaluation.policy) }
  depends_on      = [aws_iam_role_policy.evaluation, terraform_data.logs]
}
resource "aws_bedrockagentcore_online_evaluation_config" "demo" {
  online_evaluation_config_name = "${var.name}_quality"
  description                   = "Evaluate real conversations after responding, including missing-history demo"
  enable_on_create              = var.evaluation_enabled
  execution_status              = var.evaluation_enabled ? "ENABLED" : "DISABLED"
  evaluation_execution_role_arn = aws_iam_role.evaluation.arn
  data_source_config {
    cloudwatch_logs {
      log_group_names = [local.runtime_log]
      service_names   = ["${var.name}.DEFAULT"]
    }
  }
  evaluator { evaluator_id = "Builtin.Helpfulness" }
  evaluator { evaluator_id = "Builtin.GoalSuccessRate" }
  rule {
    sampling_config { sampling_percentage = 100 }
    session_config { session_timeout_minutes = 1 }
  }
  depends_on = [time_sleep.evaluation_iam, aws_cloudwatch_log_resource_policy.spans]
}
