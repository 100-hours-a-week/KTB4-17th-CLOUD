# BE의 일반 설정은 SSM, 비밀값은 Secrets Manager로 주입한다.

resource "aws_ssm_parameter" "be_config" {
  for_each = var.be_environment

  name        = "/${var.name_prefix}/prod/be/${each.key}"
  description = "Production backend config: ${each.key}"
  type        = "String"
  tier        = "Standard"
  value       = each.value

  tags = {
    Name        = "${var.name_prefix}-prod-be-${each.key}"
    environment = "prod"
  }
}

resource "aws_secretsmanager_secret" "be" {
  name                    = "${var.name_prefix}/prod/be"
  description             = "Production backend credentials and authentication secrets"
  recovery_window_in_days = 30

  tags = {
    Name        = "${var.name_prefix}-prod-be-secrets"
    environment = "prod"
  }
}

resource "aws_secretsmanager_secret_version" "be" {
  secret_id                = aws_secretsmanager_secret.be.id
  secret_string_wo         = jsonencode(merge(var.be_secret_values, var.ai_secret_values))
  secret_string_wo_version = var.be_secret_version

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  be_secret_environment_names = [
    "DB_PASSWORD",
    "JWT_SECRET",
    "CLIENT_SECRET",
    "AI_PRACTICE_API_KEY",
    "AI_PRACTICE_CALLBACK_SECRET"
  ]

  # 기존 Secrets Manager ARN을 be_secrets로 지정하면 해당 항목을 외부 Secret으로 대체한다.
  be_secret_references = merge(
    {
      for name in local.be_secret_environment_names :
      name => "${aws_secretsmanager_secret.be.arn}:${name}::"
    },
    var.be_secrets
  )

  be_environment_references = merge(
    { for name, parameter in aws_ssm_parameter.be_config : name => parameter.arn },
    local.be_secret_references
  )
}
