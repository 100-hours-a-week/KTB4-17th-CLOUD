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

variable "app_port" {
  description = "Backend container port."
  type        = number
}

variable "mysql_port" {
  description = "MySQL connection port."
  type        = number
}

variable "postgres_port" {
  description = "PostgreSQL connection port."
  type        = number
}

variable "ws_port" {
  description = "WebSocket container port."
  type        = number
}

variable "ai_port" {
  description = "AI container port."
  type        = number
}

variable "ws_database_access" {
  description = "Databases the WebSocket service may access."
  type        = set(string)
}

variable "ai_database_access" {
  description = "Databases the AI service may access."
  type        = set(string)
}

variable "v1_database_network" {
  description = "Existing v1 database network; null leaves peering and database access unmanaged."
  type = object({
    vpc_id                     = string
    route_table_ids            = set(string)
    mysql_security_group_id    = string
    postgres_security_group_id = string
  })
  default = null

  validation {
    condition = var.v1_database_network == null ? true : (
      length(var.v1_database_network.route_table_ids) > 0
    )
    error_message = "Provide the route tables actually used by the v1 database subnets."
  }
}
