variable "name" {
  type        = string
  description = "Name shared by the forwarder function, role, security group and failure queue."
  default     = "star23-prod-cloudwatch-loki"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,54}$", var.name))
    error_message = "name must contain 1-54 letters, digits, underscores or hyphens."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC containing both the Lambda subnet(s) and the existing Loki security group."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Existing subnet(s) with a local/private route to Loki. No NAT is needed for direct Loki HTTP delivery."

  validation {
    condition     = length(var.subnet_ids) > 0 && length(var.subnet_ids) <= 16
    error_message = "Supply at least one and at most 16 existing subnet IDs."
  }
}

variable "loki_security_group_id" {
  type        = string
  description = "Existing Loki EC2 security group. Only one additional ingress rule is managed."
}

variable "log_groups" {
  type        = map(string)
  description = "Existing ECS production log groups keyed by service. These log groups remain owned by the ECS module."
  default = {
    be = "/ecs/star23/prod/be"
    ws = "/ecs/star23/prod/ws"
    ai = "/ecs/star23/prod/ai"
  }

  validation {
    condition = (
      toset(keys(var.log_groups)) == toset(["be", "ws", "ai"]) &&
      alltrue([for service, group in var.log_groups : can(regex("^/ecs/[^/]+/prod/${service}$", group))])
    )
    error_message = "Supply exactly be, ws and ai, each named /ecs/<project>/prod/<service>."
  }
}

variable "lambda_log_retention_days" {
  type        = number
  description = "Retention of this forwarder's own operational logs; source ECS retention is unchanged."
  default     = 30
}

variable "enable_dlq" {
  type        = bool
  description = "Retain exhausted asynchronous invocation events in an encrypted SQS DLQ for 14 days."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Additional AWS resource tags. environment is always prod."
  default     = {}
}

variable "enable_function_connections" {
  description = "Enable invocation/permission/subscription resources after external function creation. Keep true for existing installations."
  type        = bool
  default     = true
}
