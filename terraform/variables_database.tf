variable "mysql_username" {
  description = "MySQL master username. The password is managed by RDS in Secrets Manager."
  type        = string
  default     = "star23admin"
}

variable "postgres_username" {
  description = "PostgreSQL master username. The password is managed by RDS in Secrets Manager."
  type        = string
  default     = "postgres"
}
