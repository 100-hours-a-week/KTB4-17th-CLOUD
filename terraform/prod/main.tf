module "network" {
  source = "./network"

  name_prefix         = local.name_prefix
  vpc_cidr            = local.vpc_cidr
  nat_gateway_zone    = local.nat_gateway_zone
  vpc_version         = local.version
  zones               = local.zones
  v1_database_network = var.v1_database_network
  environment         = var.environment
}

module "alb" {
  source = "./alb"

  name_prefix          = local.name_prefix
  vpc_id               = module.network.vpc_id
  public_subnet_ids    = module.network.public_subnet_ids
  app_port             = local.app_port
  health_check_path    = local.health_check_path
  ws_enabled           = var.ws_enabled
  ws_port              = var.ws_port
  ws_health_check_path = var.ws_health_check_path
  acm_certificate_arn  = var.acm_certificate_arn
}

module "database" {
  source = "./database"

  name_prefix     = local.name_prefix
  vpc_version     = local.version
  vpc_id          = module.network.vpc_id
  data_subnet_ids = module.network.data_subnet_ids
  mysql_port      = local.mysql_port
  mysql_username  = var.mysql_username

  postgres_port     = local.postgres_port
  postgres_username = var.postgres_username
}

module "storage" {
  source = "./storage"
}

module "cdn" {
  source = "./cdn"

  name_prefix = local.name_prefix
}

module "cluster" {
  source      = "./ecs/cluster"
  name_prefix = local.name_prefix
  environment = var.environment
}

module "ai" {
  source                              = "./ecs/service/ai"
  name_prefix                         = local.name_prefix
  environment                         = var.environment
  cluster_id                          = module.cluster.id
  namespace_arn                       = module.cluster.namespace_arn
  subnet_ids                          = module.network.application_subnet_ids
  vpc_id                              = module.network.vpc_id
  backend_config_references           = module.be.config_references
  ai_repository_url                   = module.storage.ai_repository_url
  ai_image_tag                        = var.ai_image_tag
  ai_port                             = var.ai_port
  ai_health_check_path                = var.ai_health_check_path
  ai_cpu_architecture                 = var.ai_cpu_architecture
  ai_desired_count                    = var.ai_desired_count
  ai_environment                      = var.ai_environment
  ai_secrets                          = var.ai_secrets
  ai_secret_kms_key_arns              = var.ai_secret_kms_key_arns
  ai_request_timeout_seconds          = var.ai_request_timeout_seconds
  ai_additional_execution_secret_arns = var.ai_additional_execution_secret_arns
  # Only the ECS service consumes these tokens; SG/config/task creation stays independent.
  traffic_rule_ids = concat(
    [
      aws_vpc_security_group_ingress_rule.ai_from_be.id,
      aws_vpc_security_group_ingress_rule.ai_from_ws.id,
    ],
    [for key, rule in aws_vpc_security_group_ingress_rule.additional_ecs_database : rule.id if local.additional_ecs_database_rules[key].service == "ai"],
    [for key, rule in aws_vpc_security_group_ingress_rule.v1_database_from_ecs : rule.id if local.v1_database_ingress_rules[key].service == "ai"],
  )

}

module "be" {
  source                 = "./ecs/service/be"
  name_prefix            = local.name_prefix
  environment            = var.environment
  cluster_id             = module.cluster.id
  namespace_arn          = module.cluster.namespace_arn
  subnet_ids             = module.network.application_subnet_ids
  vpc_id                 = module.network.vpc_id
  app_port               = local.app_port
  be_target_group_arn    = module.alb.be_target_group_arn
  be_repository_url      = module.storage.be_repository_url
  image_bucket_arn       = module.storage.image_bucket_arn
  be_image_tag           = var.be_image_tag
  be_cpu_architecture    = var.be_cpu_architecture
  be_desired_count       = var.be_desired_count
  be_environment         = var.be_environment
  be_secrets             = var.be_secrets
  be_secret_values       = var.be_secret_values
  be_secret_version      = var.be_secret_version
  be_secret_kms_key_arns = var.be_secret_kms_key_arns
  ai_secret_values       = var.ai_secret_values
  ai_service_name        = module.ai.service_name
  # Only the ECS service consumes these tokens; SG/config/task creation stays independent.
  traffic_rule_ids = concat(
    [
      aws_vpc_security_group_egress_rule.alb_to_app.id,
      aws_vpc_security_group_ingress_rule.app_from_alb.id,
      aws_vpc_security_group_ingress_rule.mysql_from_app.id,
      aws_vpc_security_group_ingress_rule.postgres_from_app.id,
      aws_vpc_security_group_ingress_rule.ai_from_be.id,
    ],
    [for key, rule in aws_vpc_security_group_ingress_rule.v1_database_from_ecs : rule.id if local.v1_database_ingress_rules[key].service == "be"],
  )

}

module "ws" {
  source                    = "./ecs/service/ws"
  name_prefix               = local.name_prefix
  environment               = var.environment
  cluster_id                = module.cluster.id
  namespace_arn             = module.cluster.namespace_arn
  subnet_ids                = module.network.application_subnet_ids
  vpc_id                    = module.network.vpc_id
  backend_config_references = module.be.config_references
  backend_kms_key_arns      = var.be_secret_kms_key_arns
  ws_target_group_arn       = module.alb.ws_target_group_arn
  image_bucket_arn          = module.storage.image_bucket_arn
  ws_enabled                = var.ws_enabled
  ws_use_backend_config     = var.ws_use_backend_config
  ws_image_uri              = var.ws_image_uri
  ws_port                   = var.ws_port
  ws_cpu_architecture       = var.ws_cpu_architecture
  ws_desired_count          = var.ws_desired_count
  ws_environment            = var.ws_environment
  ws_secrets                = var.ws_secrets
  ws_secret_kms_key_arns    = var.ws_secret_kms_key_arns
  # Only the ECS service consumes these tokens; SG/config/task creation stays independent.
  traffic_rule_ids = concat(
    [
      aws_vpc_security_group_ingress_rule.ws_from_alb.id,
      aws_vpc_security_group_egress_rule.alb_to_ws.id,
      aws_vpc_security_group_ingress_rule.ai_from_ws.id,
    ],
    [for key, rule in aws_vpc_security_group_ingress_rule.additional_ecs_database : rule.id if local.additional_ecs_database_rules[key].service == "ws"],
    [for key, rule in aws_vpc_security_group_ingress_rule.v1_database_from_ecs : rule.id if local.v1_database_ingress_rules[key].service == "ws"],
  )

}
