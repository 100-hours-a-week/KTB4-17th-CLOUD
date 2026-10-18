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
