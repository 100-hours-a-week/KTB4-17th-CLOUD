output "service_name" { value = aws_ecs_service.ai.name }
output "security_group_id" {
  value      = aws_security_group.service.id
  depends_on = [aws_vpc_security_group_egress_rule.outbound]
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
