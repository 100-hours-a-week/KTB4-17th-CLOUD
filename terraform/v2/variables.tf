variable "monitoring_security_group_id" {
  description = "V2 monitoring SG allowed to scrape the BE and WS metrics endpoints."
  type        = string
}

variable "acm_certificate_arn" {
  description = "ARN of issued ACM certificate in ap-northeast-2 for the ALB"
  type        = string
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
  description = "enabled controls WS IAM/logs/service; use_backend_config shares BE ARN/KMS/S3 permissions and enables Service Connect."
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
