locals {
  function_name = "homeops-health"
}

# Empaqueta la carpeta del código en un .zip
data "archive_file" "health" {
  type        = "zip"
  source_dir  = "${path.module}/../../api/health"
  output_path = "${path.module}/.build/health.zip"
}

# Quién puede ponerse el rol: el servicio Lambda
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# El rol con el que se ejecuta la función (encaja en homeops-app-*)
resource "aws_iam_role" "health_lambda" {
  name               = "homeops-app-health-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

# Su único permiso: escribir sus logs
resource "aws_iam_role_policy_attachment" "health_logs" {
  role       = aws_iam_role.health_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Dónde van los logs, y cuánto tiempo se guardan
resource "aws_cloudwatch_log_group" "health" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 14
}

# La función
resource "aws_lambda_function" "health" {
  function_name    = local.function_name
  role             = aws_iam_role.health_lambda.arn
  runtime          = "python3.13"
  handler          = "handler.handler"
  architectures    = ["arm64"]
  filename         = data.archive_file.health.output_path
  source_code_hash = data.archive_file.health.output_base64sha256
  memory_size      = 128
  timeout          = 5

  environment {
    variables = {
      APP_VERSION = "0.1.0"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.health_logs,
    aws_cloudwatch_log_group.health,
  ]
}