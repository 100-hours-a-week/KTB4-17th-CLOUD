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

variable "ai_database_access" {
  description = "AI access to the existing database security groups: mysql and/or postgres"
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for database in var.ai_database_access : contains(["mysql", "postgres"], database)])
    error_message = "ai_database_access may contain only mysql and postgres."
  }
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

variable "services_enabled" {
  description = "False only for first-stage fresh infrastructure bootstrap; never disable for existing services."
  type        = bool
  default     = true
}
variable "task_definition_arns" {
  description = "External revision ARNs used only for service creation. No image or runtime contents."
  type        = object({ be = optional(string), ai = optional(string), ws = optional(string) })
  default     = {}
}
variable "ws_infrastructure" {
  description = "WS infrastructure and shared permission/Service Connect switches; preserve existing settings on transition."
  type        = object({ enabled = optional(bool, true), use_backend_config = optional(bool, true) })
  default     = {}
}

variable "be_access" {
  description = "ARN-only execution permissions, without application values."
  type = object({
    secrets        = optional(map(string), {})
    kms_key_arns   = optional(set(string), [])
    parameter_arns = optional(map(string), {})
  })
  default = {}
}

variable "ai_access" {
  description = "ARN-only execution permissions, without application values."
  type = object({
    secrets                          = optional(map(string), {})
    kms_key_arns                     = optional(set(string), [])
    additional_execution_secret_arns = optional(set(string), [])
  })
  default = {}
}

variable "ws_access" {
  description = "ARN-only execution permissions, without application values."
  type = object({
    secrets      = optional(map(string), {})
    kms_key_arns = optional(set(string), [])
  })
  default = {}
}
