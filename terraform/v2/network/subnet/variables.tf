variable "vpc_id" { type = string }
variable "name_prefix" { type = string }
variable "zones" {
  description = "Availability zones and the public, application, and data subnet CIDRs."
  type = map(object({
    az          = string
    public_cidr = string
    app_cidr    = string
    data_cidr   = string
  }))
}