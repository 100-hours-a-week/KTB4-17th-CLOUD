output "alb_dns_name" {
  value = aws_alb.main.dns_name
}

output "ecs_service_names" {
  description = "Service names used by each application's CI/CD deployment"
  value = {
    be = aws_ecs_service.be.name
    ws = aws_ecs_service.ws.name
    ai = aws_ecs_service.ai.name
  }
}

output "ai_internal_url" {
  description = "AI URL for the BE tasks configured as Service Connect clients"
  value       = "http://ai:${var.ai_port}"
}

output "additional_ecs_security_group_ids" {
  description = "Security groups for the separately deployed WS and AI services"
  value = {
    for name, security_group in aws_security_group.ecs_service : name => security_group.id
  }
}
