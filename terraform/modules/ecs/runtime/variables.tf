variable "name_prefix" {
  description = "Existing AWS resource name prefix."
  type        = string
}
variable "environment" {
  description = "Environment label supplied by the composing root."
  type        = string
}
variable "service_name" {
  description = "Service identity used by the shared runtime implementation."
  type        = string
}
variable "enabled" {
  description = "Whether to manage task IAM and logs; the dedicated SG remains owned."
  type        = bool
}
variable "vpc_id" {
  description = "VPC owning this service security group."
  type        = string
}
variable "secrets" {
  description = "Secret or SSM ARN references consumed by this service."
  type        = map(string)
}
variable "kms_key_arns" {
  description = "Existing KMS key ARNs required by these secret references."
  type        = set(string)
}
variable "additional_execution_secret_arns" {
  description = "Existing secret grants required by CI task revisions."
  type        = set(string)
  default     = []
}
