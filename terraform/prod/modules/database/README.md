# Database

새 VPC의 data subnet에 MySQL·PostgreSQL RDS를 관리한다.

## 파일

- `rds-mysql.tf`: DB subnet group과 MySQL 인스턴스.
- `rds-postgres.tf`: DB subnet group과 PostgreSQL 인스턴스.
- `outputs.tf`: 앱 접속 설정에 필요한 주소, 포트, 마스터 계정 secret ARN.

## 관리 범위

DB subnet group은 `../network`의 data subnet을 사용한다.
data subnet route table에는 NAT·IGW 경로가 없어 DB는 VPC 안에서만 접근된다.
보안 그룹은 `../network`의 MySQL·PostgreSQL SG를 사용하며, BE·WS·AI의 접근 규칙도 그 모듈에서 관리한다.

마스터 비밀번호는 `manage_master_user_password`로 RDS가 Secrets Manager에 생성한다.
비밀번호는 Terraform 코드와 state에 저장되지 않는다.

`deletion_protection`과 `prevent_destroy`로 삭제를 막고, 삭제 시에도 최종 스냅샷을 남긴다.
MySQL은 이미 생성된 `star23-v2-prod-mysql`의 설정과 같다.
PostgreSQL은 v1 EC2와 같은 18.6을 사용한다.

## 연결

루트에서 data subnet ID, DB별 SG ID, 포트, 마스터 계정 이름을 전달한다.
v1 VPC의 DB는 이 모듈이 관리하지 않는다.
데이터 이전과 앱 접속 주소 변경은 별도로 진행한다.
