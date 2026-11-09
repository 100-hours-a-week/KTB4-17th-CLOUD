variable "name_prefix" {
  description = "Prefix used in AWS resource names."
  type        = string
}

variable "vpc_version" {
  description = "Version suffix retained in the database names."
  type        = string
}

variable "data_subnet_ids" {
  description = "Private data subnets in at least two AZs for the DB subnet group."
  type        = list(string)

  validation {
    condition     = length(var.data_subnet_ids) >= 2
    error_message = "An RDS subnet group needs subnets in at least two AZs."
  }
}

variable "mysql_port" {
  description = "MySQL connection port."
  type        = number
}

variable "mysql_username" {
  description = "MySQL master username. The password is managed by RDS in Secrets Manager."
  type        = string
  default     = "star23admin"
}

variable "postgres_port" {
  description = "PostgreSQL connection port."
  type        = number
}

variable "postgres_username" {
  description = "PostgreSQL master username. The password is managed by RDS in Secrets Manager."
  type        = string
  default     = "postgres"
}

variable "vpc_id" { type = string }

variable "be_security_group_id" {
  type = string
}

variable "ws_security_group_id" {
  type = string
}

variable "ai_security_group_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "v1_database_network" {
  type    = object({ mysql_security_group_id = string, postgres_security_group_id = string })
  default = null
}

variable "v1_database_peering_connection_id" {
  type    = string
  default = null
}
