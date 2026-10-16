# Root composition: network topology, followed by application infrastructure.
module "network" {
  source = "./modules/network"

  name_prefix         = local.name_prefix
  vpc_cidr            = local.vpc_cidr
  nat_gateway_zone    = local.nat_gateway_zone
  vpc_version         = local.version
  zones               = local.zones
  app_port            = local.app_port
  mysql_port          = local.mysql_port
  postgres_port       = local.postgres_port
  ws_port             = var.ws_port
  ai_port             = var.ai_port
  ws_database_access  = var.ws_database_access
  ai_database_access  = var.ai_database_access
  v1_database_network = var.v1_database_network
}

module "alb" {
  source = "./modules/alb"

  name_prefix           = local.name_prefix
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  alb_security_group_id = module.network.alb_security_group_id
  app_port              = local.app_port
  health_check_path     = local.health_check_path
  ws_enabled            = var.ws_enabled
  ws_port               = var.ws_port
  ws_health_check_path  = var.ws_health_check_path
  acm_certificate_arn   = var.acm_certificate_arn
}

module "storage" {
  source = "./modules/storage"
}

module "ecs" {
  source = "./modules/ecs"

  name_prefix                       = local.name_prefix
  app_port                          = local.app_port
  application_subnet_ids            = module.network.application_subnet_ids
  be_security_group_id              = module.network.be_security_group_id
  additional_ecs_security_group_ids = module.network.additional_ecs_security_group_ids
  be_target_group_arn               = module.alb.be_target_group_arn
  ws_target_group_arn               = module.alb.ws_target_group_arn
  be_repository_url                 = module.storage.be_repository_url
  ai_repository_url                 = module.storage.ai_repository_url
  image_bucket_arn                  = module.storage.image_bucket_arn
  be_image_tag                      = var.be_image_tag
  be_cpu_architecture               = var.be_cpu_architecture
  be_desired_count                  = var.be_desired_count
  be_environment                    = var.be_environment
  be_secrets                        = var.be_secrets
  be_secret_values                  = var.be_secret_values
  be_secret_version                 = var.be_secret_version
  be_secret_kms_key_arns            = var.be_secret_kms_key_arns
  ws_enabled                        = var.ws_enabled
  ws_use_backend_config             = var.ws_use_backend_config
  ws_image_uri                      = var.ws_image_uri
  ws_port                           = var.ws_port
  ws_health_check_path              = var.ws_health_check_path
  ws_cpu_architecture               = var.ws_cpu_architecture
  ws_desired_count                  = var.ws_desired_count
  ws_environment                    = var.ws_environment
  ws_secrets                        = var.ws_secrets
  ws_secret_kms_key_arns            = var.ws_secret_kms_key_arns
  ws_database_access                = var.ws_database_access
  ai_image_tag                      = var.ai_image_tag
  ai_port                           = var.ai_port
  ai_health_check_path              = var.ai_health_check_path
  ai_cpu_architecture               = var.ai_cpu_architecture
  ai_desired_count                  = var.ai_desired_count
  ai_environment                    = var.ai_environment
  ai_secret_values                  = var.ai_secret_values
  ai_secrets                        = var.ai_secrets
  ai_secret_kms_key_arns            = var.ai_secret_kms_key_arns
  ai_database_access                = var.ai_database_access
  ai_request_timeout_seconds        = var.ai_request_timeout_seconds
}

module "cdn" {
  source = "./modules/cdn"

  name_prefix = local.name_prefix
}
