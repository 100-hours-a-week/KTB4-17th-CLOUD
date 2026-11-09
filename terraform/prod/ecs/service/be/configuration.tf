locals {
  app_port          = 8080
  health_check_path = "/actuator/health"
}

/**
 * BE secret
 *
 * 시크릿 저장소만 생성하며, 실제 비밀번호와 토큰 값은 외부에서 주입한다.
 */
resource "aws_secretsmanager_secret" "be" {
  name                    = "${var.name_prefix}/${var.environment}/be"
  description             = "Production backend credentials and authentication secrets"
  recovery_window_in_days = 30

  tags = {
    Name        = "${var.name_prefix}-${var.environment}-be-secrets"
    environment = var.environment
  }
}

removed {
  from = aws_ssm_parameter.be_config
  lifecycle { destroy = false }
}
removed {
  from = aws_secretsmanager_secret_version.be
  lifecycle { destroy = false }
}
locals {
  be_secret_references      = merge({ container = aws_secretsmanager_secret.be.arn }, var.be_secrets)
  be_environment_references = merge(var.be_parameter_arns, local.be_secret_references)
}
