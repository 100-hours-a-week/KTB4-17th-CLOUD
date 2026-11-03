module "runtime" {
  source                           = "../../runtime"
  name_prefix                      = var.name_prefix
  environment                      = var.environment
  service_name                     = "ai"
  enabled                          = true
  vpc_id                           = var.vpc_id
  secrets                          = var.ai_secrets
  kms_key_arns                     = var.ai_secret_kms_key_arns
  additional_execution_secret_arns = var.ai_additional_execution_secret_arns
}
