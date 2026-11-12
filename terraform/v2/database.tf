/** Database connections
 * DB 소유권은 V3에 두고, V2는 기존 연결 정보만 조회한다.
 */
data "aws_db_instance" "mysql" {
  db_instance_identifier = "star23-v2-prod-mysql"
}

data "aws_db_instance" "postgres" {
  db_instance_identifier = "star23-v2-prod-postgres"
}
