locals {
  ws_port              = 8080
  ws_health_check_path = "/actuator/health"
}

locals {
  ws_secret_references = var.ws_use_backend_config ? merge(var.backend_config_references, var.ws_secrets) : var.ws_secrets
}
locals {
  additional_ecs_services = var.ws_enabled ? { ws = {
    secrets      = local.ws_secret_references
    kms_key_arns = var.ws_use_backend_config ? setunion(var.backend_kms_key_arns, var.ws_secret_kms_key_arns) : var.ws_secret_kms_key_arns
  } } : {}
}
