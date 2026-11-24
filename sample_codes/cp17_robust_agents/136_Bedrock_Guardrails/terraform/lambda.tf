resource "aws_iam_role" "lambda" {
  name = "${local.name}-role"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.amazonaws.com" }
  }] })
}

resource "aws_iam_role_policy" "inference" {
  name = "require-approved-guardrail"
  role = aws_iam_role.lambda.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    {
      Sid    = "AllowSelectedModel", Effect = "Allow",
      Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"],
      Resource = concat([data.aws_bedrock_inference_profile.model.inference_profile_arn],
      [for model in data.aws_bedrock_inference_profile.model.models : model.model_arn])
    },
    {
      # DRAFTのIAM条件は番号なしのARN。未指定・別Guardrail・公開バージョンは拒否する。
      Sid    = "DenyMissingOrDifferentGuardrail", Effect = "Deny",
      Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"], Resource = "*",
      Condition = { StringNotEquals = {
        "bedrock:GuardrailIdentifier" = aws_bedrock_guardrail.guide.guardrail_arn
      } }
    },
    {
      Sid      = "ApplyApprovedGuardrail", Effect = "Allow", Action = "bedrock:ApplyGuardrail",
      Resource = concat([aws_bedrock_guardrail.guide.guardrail_arn], local.guardrail_profiles)
    }
  ] })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = 7
}

resource "aws_iam_role_policy" "logs" {
  name = "write-function-logs"
  role = aws_iam_role.lambda.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect   = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"],
    Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
  }] })
}

# boto3はLambdaのPythonランタイム同梱版を使用する。
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../app/lambda_function.py"
  output_path = "${path.module}/../build/lambda.zip"
}

resource "aws_lambda_function" "guide" {
  function_name    = local.name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.14"
  handler          = "lambda_function.lambda_handler"
  timeout          = 120
  memory_size      = 256
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  environment {
    variables = {
      MODEL_ID          = var.model_id
      GUARDRAIL_ID      = aws_bedrock_guardrail.guide.guardrail_id
      GUARDRAIL_VERSION = "DRAFT"
    }
  }
  depends_on = [aws_iam_role_policy.inference, aws_iam_role_policy.logs]
}
