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
  description = "Non-sensitive backend environment variables"
  type        = map(string)
  default     = {}
}

variable "be_secrets" {
  description = "Backend environment variable names mapped to existing Secrets Manager or SSM parameter ARNs"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for value_from in values(var.be_secrets) :
      can(regex("^arn:aws:secretsmanager:[^:]+:[0-9]{12}:secret:[^:]+(:[^:]*){0,3}$", value_from)) ||
      can(regex("^arn:aws:ssm:[^:]+:[0-9]{12}:parameter/.+$", value_from))
    ])
    error_message = "be_secrets values must be full Secrets Manager or SSM parameter ARNs, not secret values."
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
