variable "acm_certificate_arn" {
  description = "ARN of issued ACM certificate in ap-northeast-2 for the ALB"
  type        = string
}

variable "v1_database_network" {
  description = "Existing v1 database VPC, subnet route tables, and database security groups to connect to ECS."
  type = object({
    vpc_id                     = string
    route_table_ids            = set(string)
    mysql_security_group_id    = string
    postgres_security_group_id = string
  })
  default = null
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
    condition     = length(var.be_secret_values.DB_PASSWORD) > 0 || contains(keys(var.be_runtime.secrets), "DB_PASSWORD")
    error_message = "Provide the production DB_PASSWORD at runtime, or reference an existing Secrets Manager ARN in be_secrets."
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

variable "be_secret_version" {
  description = "Increase this integer when updating the backend secret values"
  type        = number
  default     = 1

  validation {
    condition     = var.be_secret_version >= 1 && floor(var.be_secret_version) == var.be_secret_version
    error_message = "be_secret_version must be a positive integer."
  }
}

variable "be_deployment" {
  description = "BE bootstrap image and operator scaling/architecture; CI retains task revision ownership."
  type = object({
    image_tag        = string
    cpu_architecture = optional(string, "X86_64")
    desired_count    = optional(number, 2)
  })
}

variable "be_runtime" {
  description = "External BE non-secret configuration and existing secret/KMS references. Secret values use separate ephemeral inputs."
  type = object({
    environment  = optional(map(string), {})
    secrets      = optional(map(string), {})
    kms_key_arns = optional(set(string), [])
  })
  default = {}
}

variable "ai_deployment" {
  description = "AI bootstrap image and operator scaling/architecture; CI retains task revision ownership."
  type = object({
    image_tag        = string
    cpu_architecture = optional(string, "X86_64")
    desired_count    = optional(number, 2)
  })
}

variable "ai_runtime" {
  description = "External AI non-secret configuration and existing secret/KMS references. Secret values use separate ephemeral inputs."
  type = object({
    environment                      = optional(map(string), {})
    secrets                          = optional(map(string), {})
    kms_key_arns                     = optional(set(string), [])
    additional_execution_secret_arns = optional(set(string), [])
  })
  default = {}
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

variable "ws_deployment" {
  description = "WS bootstrap image and operator scaling/architecture; CI retains task revision ownership."
  type = object({
    image_uri          = string
    cpu_architecture   = optional(string, "X86_64")
    desired_count      = optional(number, 2)
    enabled            = optional(bool, true)
    use_backend_config = optional(bool, true)
  })
}

variable "ws_runtime" {
  description = "External WS non-secret configuration and existing secret/KMS references. Secret values use separate ephemeral inputs."
  type = object({
    environment  = optional(map(string), {})
    secrets      = optional(map(string), {})
    kms_key_arns = optional(set(string), [])
  })
  default = {}
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
