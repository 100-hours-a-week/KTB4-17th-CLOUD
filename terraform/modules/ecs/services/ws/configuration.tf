locals {
  ws_secret_references = var.ws_use_backend_config ? merge(var.backend_config_references, var.ws_secrets) : var.ws_secrets
}
module "runtime" {
  source                           = "../../runtime"
  name_prefix                      = var.name_prefix
  environment                      = var.environment
  service_name                     = "ws"
  enabled                          = var.ws_enabled
  vpc_id                           = var.vpc_id
  secrets                          = local.ws_secret_references
  kms_key_arns                     = var.ws_use_backend_config ? setunion(var.backend_kms_key_arns, var.ws_secret_kms_key_arns) : var.ws_secret_kms_key_arns
  additional_execution_secret_arns = []
}
