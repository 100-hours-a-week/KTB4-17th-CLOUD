locals {
  additional_ecs_services = true ? { ai = {
    secrets      = var.ai_secrets
    kms_key_arns = var.ai_secret_kms_key_arns
  } } : {}
}
