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

variable "mysql_security_group_id" {
  description = "MySQL security group in the same VPC as the data subnets."
  type        = string
}

variable "mysql_port" {
  description = "MySQL connection port."
  type        = number
}

variable "mysql_username" {
  description = "MySQL master username. The password is managed by RDS in Secrets Manager."
  type        = string
}

variable "postgres_security_group_id" {
  description = "PostgreSQL security group in the same VPC as the data subnets."
  type        = string
}

variable "postgres_port" {
  description = "PostgreSQL connection port."
  type        = number
}

variable "postgres_username" {
  description = "PostgreSQL master username. The password is managed by RDS in Secrets Manager."
  type        = string
}
