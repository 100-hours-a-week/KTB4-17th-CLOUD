variable "loki_instance_id" {
  description = "Existing monitoring EC2 that hosts Loki."
  type        = string
  default     = "i-00ed093810ec34b7d"
}

variable "loki_security_group_id" {
  description = "Existing Loki security group; existing rules are preserved."
  type        = string
  default     = "sg-0820d4fcf2170225f"
}

variable "enable_failure_queue" {
  description = "Optional SQS dead-letter queue. Enable after granting the deployment principal the scoped SQS permissions."
  type        = bool
  default     = false
}
