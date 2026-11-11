output "service_name" { value = try(aws_ecs_service.ai[0].name, null) }
output "security_group_id" {
  value = aws_security_group.service.id
}

output "port" {
  description = "Service-owned fixed configuration; independent of service readiness."
  value       = local.ai_port
}

output "health_check_path" {
  description = "Service-owned fixed configuration; independent of service readiness."
  value       = local.ai_health_check_path
}

output "request_timeout_seconds" {
  description = "Service-owned fixed configuration; independent of service readiness."
  value       = local.ai_request_timeout_seconds
}

output "deployment_infrastructure" {
  value = {
    execution_role_arn = try(aws_iam_role.service_execution["ai"].arn, null)
    task_role_arn      = try(aws_iam_role.service_task["ai"].arn, null)
    log_group_name     = try(aws_cloudwatch_log_group.service[0].name, null)
  }
}

output "ingress_rule_ids" {
  value = [aws_vpc_security_group_ingress_rule.ai_from_be.id, aws_vpc_security_group_ingress_rule.ai_from_ws.id]
}
