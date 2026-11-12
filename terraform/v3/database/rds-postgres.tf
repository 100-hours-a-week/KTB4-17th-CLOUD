/** PostgreSQL database
 * 앱과 분리된 data 서브넷 그룹과 DB 인스턴스를 함께 구성한다.
 */
resource "aws_db_subnet_group" "postgres" {
  name        = "${var.name_prefix}-${var.vpc_version}-prod-postgres-data"
  description = "Private data subnets for the new production PostgreSQL instance"
  subnet_ids  = var.data_subnet_ids

  tags = {
    Name        = "${var.name_prefix}-${var.vpc_version}-prod-postgres-data"
    environment = "prod"
  }
}

# 마스터 비밀번호는 RDS가 Secrets Manager에 생성·관리하므로 코드와 state에 남지 않는다.
resource "aws_db_instance" "postgres" {
  identifier = "${var.name_prefix}-${var.vpc_version}-prod-postgres"

  engine         = "postgres"
  engine_version = "18.6"
  instance_class = "db.t4g.small"

  allocated_storage = 50
  storage_type      = "gp3"
  storage_encrypted = true

  username                    = var.postgres_username
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  port                   = var.postgres_port
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = 3
  copy_tags_to_snapshot   = true

  # 삭제하더라도 최종 스냅샷을 남긴다.
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-${var.vpc_version}-prod-postgres-final"
  deletion_protection       = true

  tags = {
    Name        = "${var.name_prefix}-${var.vpc_version}-prod-postgres"
    environment = "prod"
  }

  lifecycle {
    prevent_destroy = true
  }
}
