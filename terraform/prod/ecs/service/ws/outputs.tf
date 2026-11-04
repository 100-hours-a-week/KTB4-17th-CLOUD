output "service_name" { value = try(aws_ecs_service.ws[0].name, null) }
output "security_group_id" {
  value      = aws_security_group.service.id
  depends_on = [aws_vpc_security_group_egress_rule.outbound]
}

output "port" {
  description = "Service-owned fixed configuration; independent of service readiness."
  value       = local.ws_port
}

output "health_check_path" {
  description = "Service-owned fixed configuration; independent of service readiness."
  value       = local.ws_health_check_path
}
