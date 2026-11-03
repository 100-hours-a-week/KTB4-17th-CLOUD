# Network

VPC, AZ별 public/application/data subnet, 공유 NAT 1개, route, peering과
공유 ALB·MySQL·PostgreSQL SG를 소유한다. 서비스 SG/IAM/log/config는 각
ECS 서비스 모듈 소유다. 서비스 간·ALB·DB의 SG 연결은 루트 `connections.tf`에 있다.

- `main.tf`, `subnets.tf`: VPC, Internet Gateway, 세 계층 subnet
- `routes.tf`, `nat.tf`: 공유 외부 통신 경로
- `security_groups.tf`, `security_rules.tf`: 공유 ALB/DB SG와 ALB listener ingress
- `peering.tf`: 기존 v1 DB VPC와의 peering 및 양방향 route

VPC/subnet 생성과 service subnet 선택을 분리한다. subnet 출력은 NAT/route 준비에
의존하며, SG 출력은 공유 SG ID만 제공한다. 서비스 출력을 다시 참조하지 않는다.

`v1_database_network`는 기존 v1 VPC/route table/DB SG ID를 받는다. v1 VPC와 DB
자체를 새로 편입하지 않는다. 실제 v1 DB SG로의 추가 ingress는 루트에서 서비스
SG ID와 peering 준비 출력을 참조한다. DB 계정, 비밀번호, DB 내부 접근 설정은
이 모듈의 소유권 밖이다.

v1 반환 route는 application `/24`만 대상으로 유지하여 다른 VPC의 기존 route를
덮어쓰지 않는다. 실제 dev EC2 편입과 backend 간 자원 이동은 이번 단계에 포함하지 않는다.

`nat_gateway_zone`의 단일 NAT를 두 AZ application subnet이 공유한다. 선택한 AZ의
NAT 장애는 양쪽 outbound에 영향을 주며, 다른 AZ에서 사용할 때 AZ 간 전송이 발생한다.
이 토폴로지와 모든 기존 CIDR/리소스 ID는 이번 리팩터링에서 유지한다.
