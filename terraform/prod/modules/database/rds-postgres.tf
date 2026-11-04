# 새 VPC의 data subnet에 PostgreSQL을 둔다. 앱 subnet과 분리되고 외부 경로가 없다.
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

  # v1 EC2의 PostgreSQL 18.6에서 데이터를 옮길 수 있도록 같은 버전을 사용한다.
  engine         = "postgres"
  engine_version = "18.6"
  instance_class = "db.t4g.small"

  allocated_storage = 50
  storage_type      = "gp3"
  storage_encrypted = true

  username                    = var.postgres_username
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [var.postgres_security_group_id]
  port                   = var.postgres_port
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = 7
  copy_tags_to_snapshot   = true

  # 삭제하더라도 최종 스냅샷을 남긴다.
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-${var.vpc_version}-prod-postgres-final"
  deletion_protection       = true

  tags = {
    Name        = "${var.name_prefix}-${var.vpc_version}-prod-postgres"
    environment = "prod"
  }

  # Terraform 명령으로 DB가 삭제되는 것을 방지한다.
  lifecycle {
    prevent_destroy = true
  }
}
