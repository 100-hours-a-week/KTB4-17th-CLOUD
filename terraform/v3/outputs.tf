output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  value = module.eks.cluster_security_group_id
}

output "private_subnet_ids" {
  value = module.eks.private_subnet_ids
}

output "node_group_names" {
  value = module.eks.node_group_names
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "mysql_address" {
  value = module.database.mysql_address
}

output "postgres_address" {
  value = module.database.postgres_address
}

output "mysql_master_user_secret_arn" {
  value = module.database.mysql_master_user_secret_arn
}

output "postgres_master_user_secret_arn" {
  value = module.database.postgres_master_user_secret_arn
}
