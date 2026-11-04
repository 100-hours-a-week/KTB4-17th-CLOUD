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
  description = "ARN references exported by the single backend configuration owner."
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

variable "traffic_rule_ids" {
  description = "Root-owned traffic rule completion tokens, consumed only by the ECS service."
  type        = list(string)
  default     = []
}
