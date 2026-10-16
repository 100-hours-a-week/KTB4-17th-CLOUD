variable "name_prefix" {
  description = "Prefix used in AWS resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC containing the load balancer and service targets."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets used by the load balancer."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group permitting listener and target traffic."
  type        = string
}

variable "app_port" {
  description = "Backend container port."
  type        = number
}

variable "health_check_path" {
  description = "Backend health check path."
  type        = string
}

variable "ws_port" {
  description = "WebSocket container port."
  type        = number
}

variable "ws_enabled" {
  description = "Forward WebSocket paths to a standalone service instead of the backend."
  type        = bool
  default     = false
}

variable "ws_health_check_path" {
  description = "WebSocket health check path."
  type        = string
}

variable "acm_certificate_arn" {
  description = "Regional ACM certificate for the HTTPS listener."
  type        = string
}
