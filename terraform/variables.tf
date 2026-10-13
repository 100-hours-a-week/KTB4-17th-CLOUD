variable "acm_certificate_arn" {
  description = "ARN of issued ACM certificate in ap-northeast-2 for the ALB"
  type        = string
}

variable "be_image_tag" {
  description = "Existing backend git SHA tag used for initial ECS creation; subsequent deployments are managed by CI/CD"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.be_image_tag))
    error_message = "be_image_tag must be a valid, non-empty ECR image tag."
  }
}

variable "be_cpu_architecture" {
  description = "CPU architecture matching the backend image: X86_64 or ARM64"
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.be_cpu_architecture)
    error_message = "be_cpu_architecture must be X86_64 or ARM64."
  }
}

variable "be_desired_count" {
  description = "Number of backend Fargate tasks"
  type        = number
  default     = 2

  validation {
    condition     = var.be_desired_count >= 0 && floor(var.be_desired_count) == var.be_desired_count
    error_message = "be_desired_count must be a non-negative integer."
  }
}

variable "be_environment" {
  description = "Non-sensitive backend config values to create as SSM String parameters and inject into ECS"
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for value in values(var.be_environment) : length(value) > 0])
    error_message = "SSM String config values cannot be empty. Fill the production DB_URL and DB_USERNAME before applying."
  }

  validation {
    condition = alltrue([
      for name in keys(var.be_environment) :
      !contains(["DB_PASSWORD", "JWT_SECRET", "CLIENT_SECRET", "AI_PRACTICE_API_KEY", "AI_PRACTICE_CALLBACK_SECRET"], name)
    ])
    error_message = "Secret values must be supplied through be_secret_values or existing Secrets Manager ARNs, not be_environment."
  }
}

variable "be_secrets" {
  description = "Optional existing Secrets Manager ARN references that override individual backend JSON secret items"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for value_from in values(var.be_secrets) :
      can(regex("^arn:aws:secretsmanager:[^:]+:[0-9]{12}:secret:[^:]+(:[^:]*){0,3}$", value_from))
    ])
    error_message = "be_secrets values must be full Secrets Manager ARNs, optionally with JSON key/version selectors."
  }
}

# 실제 값은 TF_VAR_be_secret_values 또는 Terraform 실행 시 입력으로만 전달한다.
# ephemeral 값은 write-only 필드에만 전달되어 plan/state에 저장되지 않는다.
variable "be_secret_values" {
  description = "Runtime-only backend secret values; do not put these values in tracked tfvars files"
  type = object({
    DB_PASSWORD                 = optional(string, "")
    JWT_SECRET                  = string
    CLIENT_SECRET               = string
    AI_PRACTICE_API_KEY         = optional(string, "")
    AI_PRACTICE_CALLBACK_SECRET = optional(string, "")
  })
  sensitive = true
  ephemeral = true

  validation {
    condition     = length(var.be_secret_values.JWT_SECRET) > 0 && length(var.be_secret_values.CLIENT_SECRET) > 0
    error_message = "JWT_SECRET and CLIENT_SECRET must be provided as non-empty runtime secret inputs."
  }

  validation {
    condition     = length(var.be_secret_values.DB_PASSWORD) > 0 || contains(keys(var.be_secrets), "DB_PASSWORD")
    error_message = "Provide the production DB_PASSWORD at runtime, or reference an existing Secrets Manager ARN in be_secrets."
  }
}

variable "be_secret_version" {
  description = "Increase this integer when updating the backend secret values"
  type        = number
  default     = 1

  validation {
    condition     = var.be_secret_version >= 1 && floor(var.be_secret_version) == var.be_secret_version
    error_message = "be_secret_version must be a positive integer."
  }
}

variable "be_secret_kms_key_arns" {
  description = "Customer-managed KMS key ARNs used to encrypt the referenced backend secrets, if any"
  type        = set(string)
  default     = []
}

variable "ws_image_uri" {
  description = "Full WebSocket image URI with an existing tag or sha256 digest for initial ECS creation"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9.-]+(:[0-9]+)?/[A-Za-z0-9._/-]+(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}|@sha256:[a-fA-F0-9]{64})$", var.ws_image_uri))
    error_message = "ws_image_uri must include a registry, repository, and tag or sha256 digest."
  }
}

variable "ai_image_tag" {
  description = "Existing star23/ai image tag used for initial ECS creation; later deployments are managed by CI/CD"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.ai_image_tag))
    error_message = "ai_image_tag must be a valid, non-empty ECR image tag."
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
