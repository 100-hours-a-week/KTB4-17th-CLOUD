/** MySQL security group
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

/** Existing MySQL clients
 * EKS와 외부 bastion·migration SG의 기존 접근을 보존한다.
 */
resource "aws_vpc_security_group_ingress_rule" "mysql_from_eks" {
  security_group_id            = aws_security_group.mysql.id
  referenced_security_group_id = var.eks_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.mysql_port
  to_port                      = var.mysql_port
  description                  = "EKS-v3-app-to-RDS"
}

resource "aws_vpc_security_group_ingress_rule" "mysql_from_bastion" {
  security_group_id            = aws_security_group.mysql.id
  referenced_security_group_id = var.bastion_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.mysql_port
  to_port                      = var.mysql_port
}

resource "aws_vpc_security_group_ingress_rule" "mysql_from_migration" {
  security_group_id            = aws_security_group.mysql.id
  referenced_security_group_id = var.migration_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.mysql_port
  to_port                      = var.mysql_port
  description                  = "Temporary MySQL migration access"
}

/** PostgreSQL security group
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

/** Existing PostgreSQL clients
 * EKS와 외부 bastion·migration SG의 기존 접근을 보존한다.
 */
resource "aws_vpc_security_group_ingress_rule" "postgres_from_eks" {
  security_group_id            = aws_security_group.postgres.id
  referenced_security_group_id = var.eks_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.postgres_port
  to_port                      = var.postgres_port
  description                  = "EKS v3 persona AI to shared PostgreSQL"
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_bastion" {
  security_group_id            = aws_security_group.postgres.id
  referenced_security_group_id = var.bastion_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.postgres_port
  to_port                      = var.postgres_port
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_migration" {
  security_group_id            = aws_security_group.postgres.id
  referenced_security_group_id = var.migration_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.postgres_port
  to_port                      = var.postgres_port
  description                  = "Temporary PostgreSQL migration access"
}
