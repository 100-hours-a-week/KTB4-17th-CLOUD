variable "name_prefix" {
  description = "AWS resource name prefix"
  type        = string
}

variable "app_port" {
  description = "Backend container port"
  type        = number
}

variable "application_subnet_ids" {
  description = "Private application subnets with ready outbound routes"
  type        = list(string)
}

variable "be_security_group_id" {
  description = "Backend security group with ingress and egress rules ready"
  type        = string
}

variable "additional_ecs_security_group_ids" {
  description = "WebSocket and AI security groups with ready rules"
  type        = map(string)
}

variable "be_target_group_arn" {
  description = "Backend target group attached to the ALB listeners"
  type        = string
}

variable "ws_target_group_arn" {
  description = "WebSocket target group attached to its ALB listener rule"
  type        = string
}

variable "be_repository_url" {
  description = "Backend ECR repository URL"
  type        = string
}

variable "ai_repository_url" {
  description = "AI ECR repository URL"
  type        = string
}

variable "image_bucket_arn" {
  description = "S3 bucket ARN for backend file operations"
  type        = string
}
