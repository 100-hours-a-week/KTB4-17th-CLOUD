output "mysql_address" {
  description = "MySQL hostname for application connection settings."
  value       = aws_db_instance.mysql.address
}

output "mysql_port" {
  description = "MySQL connection port."
  value       = aws_db_instance.mysql.port
}

output "mysql_master_user_secret_arn" {
  description = "Secrets Manager secret holding the MySQL master credentials."
  value       = aws_db_instance.mysql.master_user_secret[0].secret_arn
}

output "postgres_address" {
  description = "PostgreSQL hostname for application connection settings."
  value       = aws_db_instance.postgres.address
}

output "postgres_port" {
  description = "PostgreSQL connection port."
  value       = aws_db_instance.postgres.port
}

output "postgres_master_user_secret_arn" {
  description = "Secrets Manager secret holding the PostgreSQL master credentials."
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
}
