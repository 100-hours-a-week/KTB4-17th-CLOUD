locals {
  ai_port                    = 8000
  ai_health_check_path       = "/health"
  ai_request_timeout_seconds = 150

  additional_ecs_services = {
    ai = {
      secrets      = var.ai_secrets
      kms_key_arns = var.ai_secret_kms_key_arns
    }
  }
}
