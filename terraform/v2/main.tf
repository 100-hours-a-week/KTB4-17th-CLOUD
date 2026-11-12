/**
 * Network
 */
module "network" {
  source = "./network"

  name_prefix = local.name_prefix
  environment = local.environment
  vpc_version = local.version

  vpc_cidr         = local.vpc_cidr
  nat_gateway_zone = local.nat_gateway_zone
  zones            = local.zones
}

/**
 * Application load balancer
 */
module "alb" {
  source = "./alb"

  name_prefix = local.name_prefix
  environment = local.environment

  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids

  be_security_group_id = module.be.security_group_id
  ws_security_group_id = module.ws.security_group_id
  app_port             = module.be.port
  health_check_path    = module.be.health_check_path
  ws_port              = module.ws.port
  ws_health_check_path = module.ws.health_check_path
  acm_certificate_arn  = var.acm_certificate_arn
}

/**
 * ECS cluster
 */
module "cluster" {
  source = "./ecs/cluster"

  name_prefix = local.name_prefix
  environment = local.environment
}

/**
 * AI service
 */
module "ai" {
  source = "./ecs/service/ai"

  name_prefix = local.name_prefix
  environment = local.environment

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.application_subnet_ids

  cluster_id           = module.cluster.id
  namespace_arn        = module.cluster.namespace_arn
  be_security_group_id = module.be.security_group_id
  ws_security_group_id = module.ws.security_group_id

  ai_secrets                          = var.ai_access.secrets
  ai_secret_kms_key_arns              = var.ai_access.kms_key_arns
  ai_additional_execution_secret_arns = var.ai_access.additional_execution_secret_arns

  services_enabled    = var.services_enabled
  task_definition_arn = var.task_definition_arns.ai
}

/**
 * BE service
 */
module "be" {
  source = "./ecs/service/be"

  name_prefix = local.name_prefix
  environment = local.environment

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.application_subnet_ids

  cluster_id                   = module.cluster.id
  namespace_arn                = module.cluster.namespace_arn
  alb_security_group_id        = module.alb.alb_security_group_id
  be_target_group_arn          = module.alb.be_target_group_arn
  ai_service_name              = module.ai.service_name
  monitoring_security_group_id = var.monitoring_security_group_id
  traffic_rule_ids             = concat(module.alb.egress_rule_ids, module.ai.ingress_rule_ids)

  image_bucket_arn       = data.terraform_remote_state.common.outputs.image_bucket_arn
  be_secrets             = var.be_access.secrets
  be_parameter_arns      = var.be_access.parameter_arns
  migration_policy_arn   = aws_iam_policy.migration_runtime_parameters.arn
  be_secret_kms_key_arns = var.be_access.kms_key_arns

  services_enabled    = var.services_enabled
  task_definition_arn = var.task_definition_arns.be
}

/**
 * WS service
 */
module "ws" {
  source = "./ecs/service/ws"

  name_prefix = local.name_prefix
  environment = local.environment

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.application_subnet_ids

  cluster_id                   = module.cluster.id
  namespace_arn                = module.cluster.namespace_arn
  alb_security_group_id        = module.alb.alb_security_group_id
  ws_target_group_arn          = module.alb.ws_target_group_arn
  monitoring_security_group_id = var.monitoring_security_group_id
  traffic_rule_ids             = concat(module.alb.egress_rule_ids, module.ai.ingress_rule_ids)

  image_bucket_arn          = data.terraform_remote_state.common.outputs.image_bucket_arn
  backend_config_references = module.be.config_references
  backend_kms_key_arns      = var.be_access.kms_key_arns
  ws_secrets                = var.ws_access.secrets
  ws_secret_kms_key_arns    = var.ws_access.kms_key_arns
  migration_policy_arn      = aws_iam_policy.migration_runtime_parameters.arn

  ws_enabled            = var.ws_infrastructure.enabled
  ws_use_backend_config = var.ws_infrastructure.use_backend_config
  services_enabled      = var.services_enabled
  task_definition_arn   = var.task_definition_arns.ws
}
