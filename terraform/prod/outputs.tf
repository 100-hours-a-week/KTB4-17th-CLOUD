output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.alb.dns_name
}

output "ecs_service_names" {
  description = "Service names used by each application's CI/CD deployment"
  value       = merge({ be = module.be.service_name, ai = module.ai.service_name }, var.ws_infrastructure.enabled ? { ws = module.ws.service_name } : {})
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

output "deployment_infrastructure" {
  description = "Infra-only contract for externally registered task definitions; contains no secret values."
  value = {
    cluster_id        = module.cluster.id
    namespace_arn     = module.cluster.namespace_arn
    subnet_ids        = module.network.application_subnet_ids
    be                = module.be.deployment_infrastructure
    ai                = module.ai.deployment_infrastructure
    ws                = module.ws.deployment_infrastructure
    config_references = module.be.config_references
    be_repository_url = module.storage.be_repository_url
    ai_repository_url = module.storage.ai_repository_url
  }
}
