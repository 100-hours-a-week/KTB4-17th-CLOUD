variable "monitoring_security_group_id" {
  type    = string
  default = null
}

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

variable "be_target_group_arn" {
  description = "Backend target group attached to the ALB listeners"
  type        = string
}
variable "image_bucket_arn" {
  description = "S3 bucket ARN for backend file operations"
  type        = string
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
variable "be_secret_kms_key_arns" {
  description = "Customer-managed KMS key ARNs used to encrypt the referenced backend secrets, if any"
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for arn in var.be_secret_kms_key_arns : can(regex("^arn:aws:kms:[^:]+:[0-9]{12}:key/.+$", arn))])
    error_message = "Supply customer-managed KMS key ARNs only."
  }
}
variable "ai_service_name" {
  description = "AI service shell readiness; gates only BE shell creation, application readiness belongs to CI/CD."
  type        = string
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

variable "be_parameter_arns" {
  description = "External SSM parameter ARN references only; no parameter values are read or managed."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for arn in values(var.be_parameter_arns) : can(regex("^arn:aws:ssm:[^:]+:[0-9]{12}:parameter/.+$", arn))])
    error_message = "Only full SSM parameter ARNs are accepted."
  }
}

variable "alb_security_group_id" {
  type = string
}

variable "migration_policy_arn" {
  description = "Managed policy granting access to the existing migration parameter ARNs."
  type        = string
}
