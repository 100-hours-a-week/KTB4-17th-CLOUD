resource "aws_security_group" "alb" {
  vpc_id = aws_vpc.main.id

  name        = "${var.name_prefix}-alb-sg"
  description = "ALB-SG"
}

resource "aws_security_group" "mysql" {
  vpc_id = aws_vpc.main.id

  name        = "${var.name_prefix}-mysql-sg"
  description = "MYSQL-SG"
  tags        = { Name = "v2-rds-mysql" }
}

resource "aws_security_group" "postgres" {
  vpc_id = aws_vpc.main.id

  name        = "${var.name_prefix}-postgres-sg"
  description = "POSTGRES-SG"
  tags        = { Name = "v2-rds" }
}
