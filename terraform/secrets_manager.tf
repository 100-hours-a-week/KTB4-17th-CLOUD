# 비밀값 다섯 개는 한 Secret의 JSON 항목으로 관리한다.
resource "aws_secretsmanager_secret" "be" {
  name                    = "${local.name_prefix}/prod/be"
  description             = "Production backend credentials and authentication secrets"
  recovery_window_in_days = 30

  tags = {
    Name        = "${local.name_prefix}-prod-be-secrets"
    environment = "prod"
  }
}

resource "aws_secretsmanager_secret_version" "be" {
  secret_id                = aws_secretsmanager_secret.be.id
  secret_string_wo         = jsonencode(var.be_secret_values)
  secret_string_wo_version = var.be_secret_version
}
