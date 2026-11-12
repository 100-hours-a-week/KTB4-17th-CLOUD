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
variable "backend_config_references" {
  description = "ARN-only shared configuration permissions exported by BE infrastructure."
  type        = map(string)
}
variable "backend_kms_key_arns" {
  description = "KMS key ARNs for the reused backend references."
  type        = set(string)
}

variable "ws_target_group_arn" {
  description = "WebSocket target group attached to its ALB listener rule"
  type        = string
}
variable "image_bucket_arn" {
  description = "S3 bucket ARN for backend file operations"
  type        = string
}
variable "ws_enabled" {
  description = "Create WS IAM roles and logs, plus its ECS service when services_enabled is true. SG/database rules remain independent."
  type        = bool
  default     = false
}
variable "ws_use_backend_config" {
  description = "Reuse BE Secret/SSM and KMS permissions, grant image-bucket access, and enable the WS Service Connect client."
  type        = bool
  default     = false
}
variable "ws_secrets" {
  description = "ARN-only WS execution permission references; keys do not generate environment contents"
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
  validation {
    condition     = alltrue([for arn in var.ws_secret_kms_key_arns : can(regex("^arn:aws:kms:[^:]+:[0-9]{12}:key/.+$", arn))])
    error_message = "Supply customer-managed KMS key ARNs only."
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

variable "alb_security_group_id" {
  type = string
}

variable "migration_policy_arn" {
  description = "Managed policy granting access to the existing migration parameter ARNs."
  type        = string
}
