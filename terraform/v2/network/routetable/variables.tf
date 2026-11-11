variable "zones" {
  description = "Availability zones and the public, application, and data subnet CIDRs."
  type = map(object({
    az          = string
    public_cidr = string
    app_cidr    = string
    data_cidr   = string
  }))
}
variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "internet_gateway_id" { type = string }
variable "nat_gateway_id" { type = string }
variable "public_subnet_ids" { type = map(string) }
variable "application_subnet_ids" { type = map(string) }
variable "data_subnet_ids" { type = map(string) }