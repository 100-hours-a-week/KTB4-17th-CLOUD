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

module "alb" {
  source = "./alb"

  name_prefix          = local.name_prefix
  vpc_id               = module.network.vpc_id
  public_subnet_ids    = module.network.public_subnet_ids
  app_port             = module.be.port
  health_check_path    = module.be.health_check_path
  ws_enabled           = var.ws_deployment.enabled
  ws_port              = module.ws.port
  ws_health_check_path = module.ws.health_check_path
  acm_certificate_arn  = var.acm_certificate_arn
}

module "database" {
  source = "./database"

  name_prefix     = local.name_prefix
  vpc_version     = local.version
  vpc_id          = module.network.vpc_id
  data_subnet_ids = module.network.data_subnet_ids
  mysql_port      = local.mysql_port
  postgres_port   = local.postgres_port
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
  environment = local.environment
}

module "ai" {
  source                              = "./ecs/service/ai"
  name_prefix                         = local.name_prefix
  environment                         = local.environment
  cluster_id                          = module.cluster.id
  namespace_arn                       = module.cluster.namespace_arn
  subnet_ids                          = module.network.application_subnet_ids
  vpc_id                              = module.network.vpc_id
  backend_config_references           = module.be.config_references
  ai_repository_url                   = module.storage.ai_repository_url
  ai_image_tag                        = var.ai_deployment.image_tag
  ai_cpu_architecture                 = var.ai_deployment.cpu_architecture
  ai_desired_count                    = var.ai_deployment.desired_count
  ai_environment                      = var.ai_runtime.environment
  ai_secrets                          = var.ai_runtime.secrets
  ai_secret_kms_key_arns              = var.ai_runtime.kms_key_arns
  ai_additional_execution_secret_arns = var.ai_runtime.additional_execution_secret_arns
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
  environment            = local.environment
  cluster_id             = module.cluster.id
  namespace_arn          = module.cluster.namespace_arn
  subnet_ids             = module.network.application_subnet_ids
  vpc_id                 = module.network.vpc_id
  be_target_group_arn    = module.alb.be_target_group_arn
  be_repository_url      = module.storage.be_repository_url
  image_bucket_arn       = module.storage.image_bucket_arn
  be_image_tag           = var.be_deployment.image_tag
  be_cpu_architecture    = var.be_deployment.cpu_architecture
  be_desired_count       = var.be_deployment.desired_count
  be_environment         = var.be_runtime.environment
  be_secrets             = var.be_runtime.secrets
  be_secret_values       = var.be_secret_values
  be_secret_version      = var.be_secret_version
  be_secret_kms_key_arns = var.be_runtime.kms_key_arns
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
  environment               = local.environment
  cluster_id                = module.cluster.id
  namespace_arn             = module.cluster.namespace_arn
  subnet_ids                = module.network.application_subnet_ids
  vpc_id                    = module.network.vpc_id
  backend_config_references = module.be.config_references
  backend_kms_key_arns      = var.be_runtime.kms_key_arns
  ws_target_group_arn       = module.alb.ws_target_group_arn
  image_bucket_arn          = module.storage.image_bucket_arn
  ws_enabled                = var.ws_deployment.enabled
  ws_use_backend_config     = var.ws_deployment.use_backend_config
  ws_image_uri              = var.ws_deployment.image_uri
  ws_cpu_architecture       = var.ws_deployment.cpu_architecture
  ws_desired_count          = var.ws_deployment.desired_count
  ws_environment            = var.ws_runtime.environment
  ws_secrets                = var.ws_runtime.secrets
  ws_secret_kms_key_arns    = var.ws_runtime.kms_key_arns
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
