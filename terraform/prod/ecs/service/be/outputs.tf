output "service_name" { value = aws_ecs_service.be.name }
output "security_group_id" { value = aws_security_group.app.id }
output "config_references" {
  value      = local.be_environment_references
  depends_on = [aws_secretsmanager_secret_version.be]
}

output "port" { value = local.app_port }
output "health_check_path" { value = local.health_check_path }
