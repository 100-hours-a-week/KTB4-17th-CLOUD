# 새 VPC의 data subnet에 MySQL을 둔다. 앱 subnet과 분리되고 외부 경로가 없다.
resource "aws_db_subnet_group" "mysql" {
  name        = "${var.name_prefix}-${var.vpc_version}-prod-data"
  description = "Private data subnets for the new production MySQL instance"
  subnet_ids  = var.data_subnet_ids

  tags = {
    Name        = "${var.name_prefix}-${var.vpc_version}-prod-data"
    environment = "prod"
  }
}

# 마스터 비밀번호는 RDS가 Secrets Manager에 생성·관리하므로 코드와 state에 남지 않는다.
resource "aws_db_instance" "mysql" {
  identifier = "${var.name_prefix}-${var.vpc_version}-prod-mysql"

  engine         = "mysql"
  engine_version = "8.4.11"
  instance_class = "db.t4g.medium"

  allocated_storage = 50
  storage_type      = "gp3"
  storage_encrypted = true

  username                    = var.mysql_username
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [var.mysql_security_group_id]
  port                   = var.mysql_port
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = 7
  copy_tags_to_snapshot   = true

  # 삭제하더라도 최종 스냅샷을 남긴다.
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-${var.vpc_version}-prod-mysql-final"
  deletion_protection       = true

  tags = {
    Name        = "${var.name_prefix}-${var.vpc_version}-prod-mysql"
    environment = "prod"
  }

  # Terraform 명령으로 DB가 삭제되는 것을 방지한다.
  lifecycle {
    prevent_destroy = true
  }
}
