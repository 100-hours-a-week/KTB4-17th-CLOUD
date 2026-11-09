output "service_name" { value = try(aws_ecs_service.be[0].name, null) }
output "security_group_id" { value = aws_security_group.app.id }
output "config_references" {
  value = local.be_environment_references
}

output "port" { value = local.app_port }
output "health_check_path" { value = local.health_check_path }

output "deployment_infrastructure" {
  value = {
    execution_role_arn = aws_iam_role.ecs_execution.arn
    task_role_arn      = aws_iam_role.ecs_task.arn
    log_group_name     = aws_cloudwatch_log_group.service.name
  }
}
