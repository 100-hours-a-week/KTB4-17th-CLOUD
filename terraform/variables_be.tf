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
