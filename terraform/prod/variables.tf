variable "acm_certificate_arn" {
  description = "ARN of issued ACM certificate in ap-northeast-2 for the ALB"
  type        = string
}

variable "environment" {
  description = "Production label passed to reusable modules; this root retains its production backend."
  type        = string
  default     = "prod"
}
