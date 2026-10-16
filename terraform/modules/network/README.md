# Network

VPC, AZ별 public/application/data subnet, routing, 공유 NAT 1개, security group을 관리한다.

- `main.tf`: VPC와 Internet Gateway
- `subnets.tf`: 세 계층의 subnet
- `routes.tf`, `nat.tf`: 외부 통신 경로
- `security_groups.tf`: ALB, BE, WS, AI, DB security group
- `security_rules.tf`, `database_rules.tf`: 서비스와 DB 사이의 통신 허용
- `peering.tf`: 기존 v1 DB VPC와의 피어링, 양방향 경로, 실제 DB SG의 접근 규칙

루트에서 주소와 포트를 전달한다. 출력은 ALB와 ECS에 필요한 ID를 제공하며,
배포가 시작되기 전에 경로와 통신 규칙이 준비되도록 의존성을 포함한다.

VPC의 기본 CIDR은 루트 `locals.tf`의 `vpc_cidr`로 설정한다.
기존 VPC의 기본 CIDR을 바꾸면 VPC와 연결 리소스를 교체해야 한다.

`v1_database_network`에 기존 v1 VPC, DB subnet의 실제 route table, MySQL/PostgreSQL SG ID를 전달하면
같은 계정·리전의 두 VPC를 피어링한다. 기본값 `null`이면 피어링 관련 리소스를 생성하지 않는다.
v1 VPC나 DB 자체는 가져와 관리하지 않고, 새 피어링과 추가 경로·SG 규칙만 관리한다.
DB는 사설 IP로 접속하므로 피어링의 DNS 해석 옵션은 변경하지 않는다.

앱 subnet의 route table에는 v1 VPC CIDR로 향하는 경로를 추가한다.
v1 DB의 반환 경로는 새 앱 subnet의 `/24` CIDR만 대상으로 하므로,
기존 staging VPC로 향하는 `10.1.0.0/16` 경로를 덮어쓰지 않는다.
기존 v1의 route table이 두 경로를 구분할 수 있도록 다른 VPC가 사용하는 subnet 대역도 확인해야 한다.
BE에는 v1 MySQL 접근을 허용하고, WS·AI는 `ws_database_access`·`ai_database_access`에 선언한 DB만 허용한다.
이 규칙은 실제 v1 DB SG에 추가되며, 새 VPC의 MySQL/PostgreSQL SG와는 별개다.
피어링과 양방향 경로·DB SG 규칙이 준비된 뒤 ECS가 생성되도록 출력에 의존성을 둔다.

DB 내부의 접속 허용(MySQL 계정의 Host, PostgreSQL의 `pg_hba.conf`)은 기존 DB 관리 영역이다.
보안 그룹과 별도로 새 앱 subnet 대역을 허용해야 하며, 이 모듈은 DB 계정이나 인증 설정을 변경하지 않는다.

`nat_gateway_zone`으로 지정한 public subnet에 NAT를 하나 두고 두 AZ의 application subnet이 공유한다.
선택한 NAT AZ에 장애가 나면 두 AZ의 외부 통신이 영향을 받으며, 다른 AZ의 통신에는 AZ 간 전송이 발생한다.
