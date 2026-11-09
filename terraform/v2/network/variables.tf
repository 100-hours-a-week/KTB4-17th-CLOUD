variable "name_prefix" {
  description = "Prefix used in AWS resource names."
  type        = string
}

variable "vpc_cidr" {
  description = "Primary IPv4 CIDR block. Changing this value replaces the VPC."
  type        = string
}

variable "nat_gateway_zone" {
  description = "Key in zones that hosts the single NAT gateway shared by all application subnets."
  type        = string

  validation {
    condition     = contains(keys(var.zones), var.nat_gateway_zone)
    error_message = "nat_gateway_zone must be a key in zones."
  }
}

variable "vpc_version" {
  description = "Version suffix retained in the VPC name."
  type        = string
}

variable "zones" {
  description = "Availability zones and the public, application, and data subnet CIDRs."
  type = map(object({
    az          = string
    public_cidr = string
    app_cidr    = string
    data_cidr   = string
  }))
}

variable "environment" {
  type = string
}
