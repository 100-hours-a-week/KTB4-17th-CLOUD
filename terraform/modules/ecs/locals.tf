locals {
  ws_secret_references = var.ws_use_backend_config ? merge(
    local.be_environment_references,
    var.ws_secrets,
  ) : var.ws_secrets

  additional_ecs_services = merge(
    {
      ai = {
        secrets         = var.ai_secrets
        kms_key_arns    = var.ai_secret_kms_key_arns
        database_access = var.ai_database_access
      }
    },
    var.ws_enabled ? {
      ws = {
        secrets         = local.ws_secret_references
        kms_key_arns    = var.ws_use_backend_config ? setunion(var.be_secret_kms_key_arns, var.ws_secret_kms_key_arns) : var.ws_secret_kms_key_arns
        database_access = var.ws_database_access
      }
    } : {},
  )
}
