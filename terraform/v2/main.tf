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
  be_security_group_id = module.be.security_group_id
  ws_security_group_id = module.ws.security_group_id
  environment          = local.environment
  source               = "./alb"

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
  be_security_group_id              = module.be.security_group_id
  ws_security_group_id              = module.ws.security_group_id
  ai_security_group_id              = module.ai.security_group_id
  environment                       = local.environment
  v1_database_network               = var.v1_database_network
  v1_database_peering_connection_id = module.network.v1_database_peering_connection_id
  source                            = "./database"

  name_prefix     = local.name_prefix
  vpc_version     = local.version
  vpc_id          = module.network.vpc_id
  data_subnet_ids = module.network.data_subnet_ids
  mysql_port      = local.mysql_port
  postgres_port   = local.postgres_port
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
  be_security_group_id                = module.be.security_group_id
  ws_security_group_id                = module.ws.security_group_id
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
  traffic_rule_ids                    = module.database.ai_rule_ids

}

/**
 * BE service
 */
module "be" {
  alb_security_group_id  = module.alb.alb_security_group_id
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
  image_bucket_arn       = data.terraform_remote_state.common.outputs.image_bucket_arn
  be_secrets             = var.be_access.secrets
  be_parameter_arns      = var.be_access.parameter_arns
  be_secret_kms_key_arns = var.be_access.kms_key_arns
  ai_service_name        = module.ai.service_name
  traffic_rule_ids       = concat(module.alb.egress_rule_ids, module.database.be_rule_ids, module.ai.ingress_rule_ids)

}

/**
 * WS service
 */
module "ws" {
  alb_security_group_id     = module.alb.alb_security_group_id
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
  image_bucket_arn          = data.terraform_remote_state.common.outputs.image_bucket_arn
  ws_enabled                = var.ws_infrastructure.enabled
  ws_use_backend_config     = var.ws_infrastructure.use_backend_config
  ws_secrets                = var.ws_access.secrets
  ws_secret_kms_key_arns    = var.ws_access.kms_key_arns
  traffic_rule_ids          = concat(module.alb.egress_rule_ids, module.database.ws_rule_ids, module.ai.ingress_rule_ids)

}
