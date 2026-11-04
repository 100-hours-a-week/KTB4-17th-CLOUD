# Network

`main.tf`가 실제 `vpc/`, `subnet/`, `routetable/` 하위 모듈을 조합한다.
VPC/IGW, AZ별 public/application/data subnet, route table/association/default route를 각각 소유한다.
`nat.tf`는 기존 단일 NAT/EIP, `peering.tf`는 V1 peering과 양방향 granular route를 유지한다.
ALB·DB SG와 base rule은 각 소비자의 `security.tf`, 교차 연결은 prod `connections.tf` 소유다.

public subnet 출력은 IGW/default route/association, application 출력은 NAT 및 양방향 V1 route,
data 출력은 association의 완료를 전달한다. 서비스 출력을 역참조하거나 모듈 전체 gate를 만들지 않는다.
V1 VPC 자체와 기존 DB는 참조만 한다. V1 반환 route는 application `/24`만 대상으로 유지한다.

기존 `nat_gateway_zone`의 NAT 1개를 두 AZ가 공유한다. 해당 NAT 장애는 양쪽 outbound에
영향을 주고 다른 AZ 사용 시 AZ 간 전송이 발생한다. 이 토폴로지와 기존 CIDR/ID를 보존한다.
