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

variable "loki_write_address" {
  type        = string
  description = "Private Loki push URL, reachable through the Loki security group on TCP 3100."
  default     = "http://10.0.1.88:3100/loki/api/v1/push"

  validation {
    condition     = can(regex("^http://[^/]+:3100/loki/api/v1/push$", var.loki_write_address))
    error_message = "Use a private Loki HTTP endpoint on port 3100 ending in /loki/api/v1/push."
  }
}

variable "lambda_zip_path" {
  type        = string
  description = "Verified lambda-promtail ZIP with an executable x86_64 bootstrap at archive root (v1.0.1)."
}

variable "lambda_zip_sha256" {
  type        = string
  description = "Expected SHA-256 of the pinned upstream ZIP; update only after verifying a new release."
  default     = "2a436a30772ac638f715dd240784f787b9f0c745ba292a49cd23d132c477fd13"

  validation {
    condition     = can(regex("^[a-f0-9]{64}$", var.lambda_zip_sha256))
    error_message = "lambda_zip_sha256 must be a lowercase 64-character SHA-256 digest."
  }
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

variable "extra_labels" {
  type        = map(string)
  description = "Optional low-cardinality labels. environment=prod, job=ecs and source=cloudwatch are always set by this module."
  default = {
    cluster = "star23-ecs-cluster"
  }

  validation {
    condition = alltrue([
      for name, value in var.extra_labels :
      can(regex("^[A-Za-z_][A-Za-z0-9_]*$", name)) && !strcontains(value, ",") &&
      !contains(["service", "ecs_service", "cloudwatch_log_group"], name)
    ])
    error_message = "Labels must have valid names and comma-free values; service, ecs_service and cloudwatch_log_group are derived from CloudWatch."
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

variable "reserved_concurrency" {
  type        = number
  description = "Concurrent Loki writers. Use -1 to use the account's unreserved concurrency pool."
  default     = -1

  validation {
    condition     = var.reserved_concurrency == -1 || var.reserved_concurrency >= 1
    error_message = "reserved_concurrency must be -1 or at least 1."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional AWS resource tags. environment is always prod."
  default     = {}
}
