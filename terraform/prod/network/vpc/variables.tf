variable "name_prefix" {
  description = "Prefix used in AWS resource names."
  type        = string
}

variable "vpc_cidr" {
  description = "Primary IPv4 CIDR block. Changing this value replaces the VPC."
  type        = string
}

variable "vpc_version" {
  description = "Version suffix retained in the VPC name."
  type        = string
}