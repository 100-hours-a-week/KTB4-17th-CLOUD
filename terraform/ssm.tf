# 일반 설정은 SSM String으로 관리하고, ECS의 secrets 필드에서 ARN을 참조한다.
resource "aws_ssm_parameter" "be_config" {
  for_each = var.be_environment

  name        = "/${local.name_prefix}/prod/be/${each.key}"
  description = "Production backend config: ${each.key}"
  type        = "String"
  tier        = "Standard"
  value       = each.value

  tags = {
    Name        = "${local.name_prefix}-prod-be-${each.key}"
    environment = "prod"
  }
}
