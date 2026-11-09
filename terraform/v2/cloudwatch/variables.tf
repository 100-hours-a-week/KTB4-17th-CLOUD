variable "monitoring_ami_id" {
  description = "Private recovery AMI containing the preserved monitoring data."
  type        = string
}

variable "monitoring_vpc_id" {
  description = "Existing V2 VPC; its lifecycle remains owned by the V2 root."
  type        = string
  default     = "vpc-021d4bdf5e5e79b3e"
}

variable "monitoring_subnet_id" {
  description = "Existing V2 public subnet; EC2 explicitly requests an ordinary public IPv4."
  type        = string
  default     = "subnet-0ed1f69eb87aa7bb0"
}

variable "monitoring_ssh_cidrs" {
  description = "Existing public administrator SSH ranges, supplied outside the repository."
  type        = set(string)
}

variable "monitoring_grafana_admin_cidrs" {
  description = "Existing direct Grafana administrator ranges, supplied outside the repository."
  type        = set(string)
}

variable "enable_failure_queue" {
  description = "Optional SQS dead-letter queue. Enable after granting the deployment principal the scoped SQS permissions."
  type        = bool
  default     = false
}

variable "enable_function_connections" {
  description = "False only during fresh infrastructure stage, true after external Lambda creation. Keep true for existing logging."
  type        = bool
  default     = true
}
