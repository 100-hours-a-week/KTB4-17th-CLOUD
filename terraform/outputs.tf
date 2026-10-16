output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.alb.dns_name
}

output "ecs_service_names" {
  description = "Service names used by each application's CI/CD deployment"
  value       = module.ecs.service_names
}

output "ai_internal_url" {
  description = "AI URL for the BE tasks configured as Service Connect clients"
  value       = module.ecs.ai_internal_url
}

output "additional_ecs_security_group_ids" {
  description = "Security groups for the separately deployed WS and AI services"
  value       = module.network.additional_ecs_security_group_ids
}
