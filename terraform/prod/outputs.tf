output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.alb.dns_name
}

output "ecs_service_names" {
  description = "Service names used by each application's CI/CD deployment"
  value       = merge({ be = module.be.service_name, ai = module.ai.service_name }, var.ws_deployment.enabled ? { ws = module.ws.service_name } : {})
}

output "ai_internal_url" {
  description = "AI URL for the BE tasks configured as Service Connect clients"
  value       = "http://ai:${module.ai.port}"
}

output "additional_ecs_security_group_ids" {
  description = "Security groups for the separately deployed WS and AI services"
  value       = { ws = module.ws.security_group_id, ai = module.ai.security_group_id }
}

output "mysql_address" {
  description = "MySQL hostname in the application VPC"
  value       = module.database.mysql_address
}

output "mysql_master_user_secret_arn" {
  description = "Secrets Manager secret holding the MySQL master credentials"
  value       = module.database.mysql_master_user_secret_arn
}

output "postgres_address" {
  description = "PostgreSQL hostname in the application VPC"
  value       = module.database.postgres_address
}

output "postgres_master_user_secret_arn" {
  description = "Secrets Manager secret holding the PostgreSQL master credentials"
  value       = module.database.postgres_master_user_secret_arn
}
