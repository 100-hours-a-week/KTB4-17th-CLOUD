/**
 * Network
 */
module "network" {
  source = "./network"

  name_prefix         = local.name_prefix
  vpc_cidr            = local.vpc_cidr
  nat_gateway_zone    = local.nat_gateway_zone
  vpc_version         = local.version
  zones               = local.zones
  v1_database_network = var.v1_database_network
  environment         = local.environment
}

/**
 * Application load balancer
 */
module "alb" {
  source = "./alb"

  name_prefix          = local.name_prefix
  vpc_id               = module.network.vpc_id
  public_subnet_ids    = module.network.public_subnet_ids
  app_port             = module.be.port
  health_check_path    = module.be.health_check_path
  ws_port              = module.ws.port
  ws_health_check_path = module.ws.health_check_path
  acm_certificate_arn  = var.acm_certificate_arn
}

/**
 * Databases
 */
module "database" {
  source = "./database"

  name_prefix     = local.name_prefix
  vpc_version     = local.version
  vpc_id          = module.network.vpc_id
  data_subnet_ids = module.network.data_subnet_ids
  mysql_port      = local.mysql_port
  postgres_port   = local.postgres_port
}

/**
 * Storage
 */
module "storage" {
  source = "./storage"
}

/**
 * CDN
 */
module "cdn" {
  source = "./cdn"

  name_prefix = local.name_prefix
}

/**
 * ECS cluster
 */
module "cluster" {
  source      = "./ecs/cluster"
  name_prefix = local.name_prefix
  environment = local.environment
}

/**
 * AI service
 */
module "ai" {
  services_enabled                    = var.services_enabled
  task_definition_arn                 = var.task_definition_arns.ai
  source                              = "./ecs/service/ai"
  name_prefix                         = local.name_prefix
  environment                         = local.environment
  cluster_id                          = module.cluster.id
  namespace_arn                       = module.cluster.namespace_arn
  subnet_ids                          = module.network.application_subnet_ids
  vpc_id                              = module.network.vpc_id
  ai_secrets                          = var.ai_access.secrets
  ai_secret_kms_key_arns              = var.ai_access.kms_key_arns
  ai_additional_execution_secret_arns = var.ai_access.additional_execution_secret_arns
  # Only the ECS service consumes these tokens; SG/IAM/log creation stays independent.
  traffic_rule_ids = concat(
    [
      aws_vpc_security_group_ingress_rule.ai_from_be.id,
      aws_vpc_security_group_ingress_rule.ai_from_ws.id,
    ],
    [for key, rule in aws_vpc_security_group_ingress_rule.additional_ecs_database : rule.id if local.additional_ecs_database_rules[key].service == "ai"],
    [for key, rule in aws_vpc_security_group_ingress_rule.v1_database_from_ecs : rule.id if local.v1_database_ingress_rules[key].service == "ai"],
  )

}

/**
 * BE service
 */
module "be" {
  services_enabled       = var.services_enabled
  task_definition_arn    = var.task_definition_arns.be
  source                 = "./ecs/service/be"
  name_prefix            = local.name_prefix
  environment            = local.environment
  cluster_id             = module.cluster.id
  namespace_arn          = module.cluster.namespace_arn
  subnet_ids             = module.network.application_subnet_ids
  vpc_id                 = module.network.vpc_id
  be_target_group_arn    = module.alb.be_target_group_arn
  image_bucket_arn       = module.storage.image_bucket_arn
  be_secrets             = var.be_access.secrets
  be_parameter_arns      = var.be_access.parameter_arns
  be_secret_kms_key_arns = var.be_access.kms_key_arns
  ai_service_name        = module.ai.service_name
  # Only the ECS service consumes these tokens; SG/IAM/log creation stays independent.
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

/**
 * WS service
 */
module "ws" {
  services_enabled          = var.services_enabled
  task_definition_arn       = var.task_definition_arns.ws
  source                    = "./ecs/service/ws"
  name_prefix               = local.name_prefix
  environment               = local.environment
  cluster_id                = module.cluster.id
  namespace_arn             = module.cluster.namespace_arn
  subnet_ids                = module.network.application_subnet_ids
  vpc_id                    = module.network.vpc_id
  backend_config_references = module.be.config_references
  backend_kms_key_arns      = var.be_access.kms_key_arns
  ws_target_group_arn       = module.alb.ws_target_group_arn
  image_bucket_arn          = module.storage.image_bucket_arn
  ws_enabled                = var.ws_infrastructure.enabled
  ws_use_backend_config     = var.ws_infrastructure.use_backend_config
  ws_secrets                = var.ws_access.secrets
  ws_secret_kms_key_arns    = var.ws_access.kms_key_arns
  # Only the ECS service consumes these tokens; SG/IAM/log creation stays independent.
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
