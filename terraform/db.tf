# 기존 staging RDS가 사용하는 private subnet group을 관리한다.
# subnet ID는 현재 star23-v2-private DB subnet group의 실제 구성이다.
resource "aws_db_subnet_group" "mysql" {
  name = "star23-v2-private"
  subnet_ids = [
    "subnet-055004600adc2a057",
    "subnet-090557aada05e25f3",
  ]

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [description]
  }
}

# 기존 staging MySQL 인스턴스를 관리한다.
# 사용자명과 비밀번호 같은 인증 정보는 Terraform 코드 밖에서 관리한다.
resource "aws_db_instance" "mysql" {
  identifier = "star23-v2-staging-mysql"

  engine         = "mysql"
  engine_version = "8.4.11"
  instance_class = "db.t4g.medium"

  allocated_storage = 50
  storage_type      = "gp3"
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = ["sg-09526ecdbb0b3e122"]
  port                   = local.mysql_port
  publicly_accessible    = false
  multi_az               = false

  # 삭제 방지를 해제하더라도 최종 스냅샷 없이는 DB가 삭제되지 않게 한다.
  skip_final_snapshot = false

  # 기존 운영 DB가 Terraform 명령으로 삭제되는 것을 방지한다.
  lifecycle {
    prevent_destroy = true
  }
}

# 기존 DB subnet group을 새로 생성하지 않고 Terraform 상태에 연결한다.
import {
  to = aws_db_subnet_group.mysql
  id = "star23-v2-private"
}

# 기존 RDS 인스턴스를 새로 생성하지 않고 Terraform 상태에 연결한다.
import {
  to = aws_db_instance.mysql
  id = "star23-v2-staging-mysql"
}
