/**
 * MySQL security group
 */
resource "aws_security_group" "mysql" {
  vpc_id = var.vpc_id

  name        = "${var.name_prefix}-mysql-sg"
  description = "MYSQL-SG"
  tags        = { Name = "v2-rds-mysql" }
}

/**
 * PostgreSQL security group
 */
resource "aws_security_group" "postgres" {
  vpc_id = var.vpc_id

  name        = "${var.name_prefix}-postgres-sg"
  description = "POSTGRES-SG"
  tags        = { Name = "v2-rds" }
}
