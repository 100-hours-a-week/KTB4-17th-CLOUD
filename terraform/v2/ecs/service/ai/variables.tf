variable "name_prefix" {
  description = "Existing AWS resource name prefix."
  type        = string
}
variable "environment" {
  description = "Environment label supplied by the composing root."
  type        = string
}
variable "cluster_id" {
  description = "Shared ECS cluster ID."
  type        = string
}
variable "namespace_arn" {
  description = "Shared Service Connect namespace ARN."
  type        = string
}
variable "subnet_ids" {
  description = "Selected service placement in shared network subnets."
  type        = list(string)
}
variable "vpc_id" {
  description = "VPC owning this service security group."
  type        = string
}

variable "ai_secrets" {
  description = "ARN-only AI execution permission references; keys do not generate environment contents"
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
  validation {
    condition     = alltrue([for arn in var.ai_secret_kms_key_arns : can(regex("^arn:aws:kms:[^:]+:[0-9]{12}:key/.+$", arn))])
    error_message = "Supply customer-managed KMS key ARNs only."
  }
}
variable "ai_additional_execution_secret_arns" {
  description = "Existing Secrets Manager grants used by CI-managed AI task revisions owned by external deployment."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.ai_additional_execution_secret_arns :
      can(regex("^arn:aws:secretsmanager:[^:]+:[0-9]{12}:secret:[^:]+$", arn))
    ])
    error_message = "Supply existing Secrets Manager ARNs without JSON key or version selectors."
  }
}

variable "traffic_rule_ids" {
  description = "Peer-owned traffic rule completion tokens, consumed only by the ECS service."
  type        = list(string)
  default     = []
}

variable "services_enabled" {
  description = "Create service shells only after external task registration. False is for fresh infrastructure only."
  type        = bool
  default     = true
}
variable "task_definition_arn" {
  description = "Externally registered task ARN; used only when creating the zero-task service shell."
  type        = string
  default     = null
  validation {
    condition     = var.task_definition_arn == null ? true : can(regex("^arn:aws:ecs:[^:]+:[0-9]{12}:task-definition/[^:]+:[0-9]+$", var.task_definition_arn))
    error_message = "Supply a full ECS task definition ARN including revision."
  }
}

variable "be_security_group_id" {
  type = string
}

variable "ws_security_group_id" {
  type = string
}
