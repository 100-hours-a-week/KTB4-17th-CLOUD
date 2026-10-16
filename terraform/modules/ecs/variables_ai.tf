variable "ai_image_tag" {
  description = "Existing star23/ai image tag used for initial ECS creation; later deployments are managed by CI/CD"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.ai_image_tag))
    error_message = "ai_image_tag must be a valid, non-empty ECR image tag."
  }
}

variable "ai_port" {
  description = "AI application listening port; the server must bind to 0.0.0.0"
  type        = number

  validation {
    condition     = var.ai_port >= 1 && var.ai_port <= 65535 && floor(var.ai_port) == var.ai_port
    error_message = "ai_port must be an integer from 1 to 65535."
  }
}

variable "ai_health_check_path" {
  description = "AI HTTP readiness endpoint that returns status 200 without authentication"
  type        = string

  validation {
    condition     = startswith(var.ai_health_check_path, "/") && length(var.ai_health_check_path) <= 1024
    error_message = "ai_health_check_path must start with / and contain at most 1024 characters."
  }
}

variable "ai_cpu_architecture" {
  description = "AI image CPU architecture: X86_64 or ARM64"
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.ai_cpu_architecture)
    error_message = "ai_cpu_architecture must be X86_64 or ARM64."
  }
}

variable "ai_desired_count" {
  description = "AI Fargate task count"
  type        = number
  default     = 2

  validation {
    condition     = var.ai_desired_count >= 0 && floor(var.ai_desired_count) == var.ai_desired_count
    error_message = "ai_desired_count must be a non-negative integer."
  }
}

variable "ai_environment" {
  description = "AI non-sensitive environment variables"
  type        = map(string)
  default     = {}
}

variable "ai_secrets" {
  description = "AI environment variable names mapped to existing Secrets Manager or SSM parameter ARNs"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for value_from in values(var.ai_secrets) :
      can(regex("^arn:aws:secretsmanager:[^:]+:[0-9]{12}:secret:[^:]+(:[^:]*){0,3}$", value_from)) ||
      can(regex("^arn:aws:ssm:[^:]+:[0-9]{12}:parameter/.+$", value_from))
    ])
    error_message = "ai_secrets values must be full Secrets Manager or SSM parameter ARNs, not secret values."
  }
}

variable "ai_secret_kms_key_arns" {
  description = "Customer-managed KMS key ARNs encrypting the referenced AI secrets, if any"
  type        = set(string)
  default     = []
}

variable "ai_database_access" {
  description = "AI access to the existing database security groups: mysql and/or postgres"
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for database in var.ai_database_access : contains(["mysql", "postgres"], database)])
    error_message = "ai_database_access may contain only mysql and postgres."
  }
}

variable "ai_request_timeout_seconds" {
  description = "Service Connect AI request timeout in seconds; 0 disables the request timeout"
  type        = number
  default     = 120

  validation {
    condition     = var.ai_request_timeout_seconds >= 0 && var.ai_request_timeout_seconds <= 2147483647 && floor(var.ai_request_timeout_seconds) == var.ai_request_timeout_seconds
    error_message = "ai_request_timeout_seconds must be a non-negative integer no greater than 2147483647."
  }
}
variable "ai_secret_values" {
  description = "Runtime-only AI secrets stored as AI_* fields alongside backend secrets; never put values in tfvars."
  type        = map(string)
  default     = {}
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = alltrue([for name in keys(var.ai_secret_values) : startswith(name, "AI_")])
    error_message = "AI runtime secret keys must start with AI_ to avoid overwriting backend credentials."
  }
}
