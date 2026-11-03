variable "name_prefix" {
  description = "Existing AWS resource name prefix."
  type        = string
}
variable "environment" {
  description = "Environment label supplied by the composing root."
  type        = string
}
