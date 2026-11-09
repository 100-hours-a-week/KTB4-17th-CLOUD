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

variable "ai_repository_url" {
  description = "AI ECR repository URL"
  type        = string
}
variable "ai_image_tag" {
  description = "Existing star23/ai image tag used for initial ECS creation; later deployments are managed by CI/CD"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.ai_image_tag))
    error_message = "ai_image_tag must be a valid, non-empty ECR image tag."
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
variable "ai_additional_execution_secret_arns" {
  description = "Existing Secrets Manager grants used by CI-managed AI task revisions beyond the Terraform bootstrap definition."
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

variable "backend_config_references" {
  description = "Shared config ARN references; the BE output also waits for its Secret version."
  type        = map(string)
}

variable "traffic_rule_ids" {
  description = "Root-owned traffic rule completion tokens, consumed only by the ECS service."
  type        = list(string)
  default     = []
}
