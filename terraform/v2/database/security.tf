/**
 * MySQL security group
 *
 * 보안 그룹과 확인된 서비스 접근 규칙을 함께 관리한다.
 */
resource "aws_security_group" "mysql" {
  vpc_id = var.vpc_id

  name        = "${var.name_prefix}-mysql-sg"
  description = "MYSQL-SG"
  tags        = { Name = "v2-rds-mysql" }
}

resource "aws_vpc_security_group_ingress_rule" "mysql_from_app" {
  security_group_id = aws_security_group.mysql.id

  referenced_security_group_id = var.be_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.mysql_port
  to_port                      = var.mysql_port

  tags = {
    Name = "${var.name_prefix}-mysql-from-app-ingress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "mysql_from_ws" {
  security_group_id            = aws_security_group.mysql.id
  referenced_security_group_id = var.ws_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.mysql_port
  to_port                      = var.mysql_port
  tags = {
    Name        = "${var.name_prefix}-mysql-from-ws"
    environment = var.environment
  }
}

/**
 * PostgreSQL security group
 *
 * 보안 그룹과 확인된 서비스 접근 규칙을 함께 관리한다.
 */
resource "aws_security_group" "postgres" {
  vpc_id = var.vpc_id

  name        = "${var.name_prefix}-postgres-sg"
  description = "POSTGRES-SG"
  tags        = { Name = "v2-rds" }
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_app" {
  security_group_id = aws_security_group.postgres.id

  referenced_security_group_id = var.be_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.postgres_port
  to_port                      = var.postgres_port

  tags = {
    Name = "${var.name_prefix}-postgres-from-app-ingress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_ai" {
  security_group_id            = aws_security_group.postgres.id
  referenced_security_group_id = var.ai_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.postgres_port
  to_port                      = var.postgres_port
  tags = {
    Name        = "${var.name_prefix}-postgres-from-ai"
    environment = var.environment
  }
}
