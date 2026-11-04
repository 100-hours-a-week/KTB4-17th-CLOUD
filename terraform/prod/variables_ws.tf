variable "ws_enabled" {
  description = "Deploy a standalone WebSocket service; disabled when the backend handles WebSocket traffic."
  type        = bool
  default     = false
}

variable "ws_use_backend_config" {
  description = "Reuse backend SSM, secret, S3, and Service Connect configuration for a WebSocket task running the backend image."
  type        = bool
  default     = false
}

variable "ws_image_uri" {
  description = "Full WebSocket image URI with an existing tag or sha256 digest for initial ECS creation"
  type        = string
  default     = ""

  validation {
    condition     = !var.ws_enabled || can(regex("^[A-Za-z0-9.-]+(:[0-9]+)?/[A-Za-z0-9._/-]+(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}|@sha256:[a-fA-F0-9]{64})$", var.ws_image_uri))
    error_message = "When ws_enabled is true, ws_image_uri must include a registry, repository, and tag or sha256 digest."
  }
}

variable "ws_port" {
  description = "WebSocket application listening port; the server must bind to 0.0.0.0"
  type        = number

  validation {
    condition     = var.ws_port >= 1 && var.ws_port <= 65535 && floor(var.ws_port) == var.ws_port
    error_message = "ws_port must be an integer from 1 to 65535."
  }
}

variable "ws_health_check_path" {
  description = "WebSocket HTTP readiness endpoint that returns status 200 without authentication"
  type        = string

  validation {
    condition     = startswith(var.ws_health_check_path, "/") && length(var.ws_health_check_path) <= 1024
    error_message = "ws_health_check_path must start with / and contain at most 1024 characters."
  }
}

variable "ws_cpu_architecture" {
  description = "WebSocket image CPU architecture: X86_64 or ARM64"
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.ws_cpu_architecture)
    error_message = "ws_cpu_architecture must be X86_64 or ARM64."
  }
}

variable "ws_desired_count" {
  description = "WebSocket Fargate task count"
  type        = number
  default     = 2

  validation {
    condition     = var.ws_desired_count >= 0 && floor(var.ws_desired_count) == var.ws_desired_count
    error_message = "ws_desired_count must be a non-negative integer."
  }
}

variable "ws_environment" {
  description = "WebSocket non-sensitive environment variables"
  type        = map(string)
  default     = {}
}

variable "ws_secrets" {
  description = "WebSocket environment variable names mapped to existing Secrets Manager or SSM parameter ARNs"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for value_from in values(var.ws_secrets) :
      can(regex("^arn:aws:secretsmanager:[^:]+:[0-9]{12}:secret:[^:]+(:[^:]*){0,3}$", value_from)) ||
      can(regex("^arn:aws:ssm:[^:]+:[0-9]{12}:parameter/.+$", value_from))
    ])
    error_message = "ws_secrets values must be full Secrets Manager or SSM parameter ARNs, not secret values."
  }
}

variable "ws_secret_kms_key_arns" {
  description = "Customer-managed KMS key ARNs encrypting the referenced WebSocket secrets, if any"
  type        = set(string)
  default     = []
}

variable "ws_database_access" {
  description = "WebSocket access to the existing database security groups: mysql and/or postgres"
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for database in var.ws_database_access : contains(["mysql", "postgres"], database)])
    error_message = "ws_database_access may contain only mysql and postgres."
  }
}
