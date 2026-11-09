# 개발 인프라

독립 실행 루트이며 backend는 `dev/terraform.tfstate`다. EC2 3개와 기존 V1 네트워크를 관리한다. SG·EIP·IAM과 VPC 간 peering은 외부 소유로 유지한다. 운영 루트와 합쳐 실행하지 않는다.

## V1 네트워크 편입

`network`는 기존 자원을 조회하는 `data` 대신 `resource`로 선언한다. `imports.tf`는 VPC 1개, IGW 1개, 서브넷 2개, public/default 라우팅 테이블 2개, 인터넷 기본 경로 1개, 서브넷 연결 2개를 기존 ID 그대로 편입하는 일회성 선언이다. apply 전까지 원격 dev state 소유권은 바뀌지 않는다. 편입 완료 후 `imports.tf`만 제거하고 resource 선언은 유지한다.

DNS hostnames 비활성화, 서브넷의 public IP 자동 할당 비활성화, 기존 CIDR·AZ·태그를 실제 AWS와 동일하게 유지한다. EC2가 참조하던 서브넷 map의 키와 ID도 유지한다. `network` 출력은 관리하는 VPC·서브넷·라우팅 테이블·IGW ID를 제공한다.

2026-11-09 현재 bucket의 여섯 state에서 중복 소유권을 조사했다. 네트워크 9개 편입 대상은 기존 managed 소유자가 없고, public 테이블의 `10.1.64.0/24`, `10.1.65.0/24` 두 경로는 prod state가 소유한다. 이 모듈은 inline `route`나 `route = []`를 선언하지 않고 인터넷 기본 경로만 별도 `aws_route`로 관리한다. 따라서 prod 소유 경로와 외부에서 관리하는 나머지 peering 경로를 덮어쓰지 않는다. AWS가 자동 생성한 main/default 테이블은 `aws_default_route_table`로 편입하며 직접 삭제하지 않는다.

V1 VPC에는 dev EC2 외에도 운영 Loki EC2, 로그 전달 Lambda ENI, GPU EC2가 있다. 공유 VPC·IGW·서브넷·테이블·인터넷 경로·연결에는 `prevent_destroy`를 둔다. **현재 dev 전체 destroy는 삭제 보호로 차단된다.** V1을 독립적으로 철거하려면 공유 소비자와 prod peering 경로를 먼저 분리하고, 외부 SG·EIP·IAM 범위도 따로 정해야 한다. 단순한 편입이 공유 의존성 분리까지 완료시키는 것은 아니다.

편입 검토에서는 정확한 9개 import와 기존 EC2 3개의 no-op만 허용한다. 생성·수정·삭제·교체나 다른 ID가 보이면 적용하지 않는다. 직전 검토 이후 다른 state의 소유권 변경이 없는지도 다시 확인한다. 실제 AWS 변경 및 원격 state 편입은 별도 운영 실행 단계다.

2026-11-09 검증에서는 backend를 제거한 임시 사본과 원격 dev state의 로컬 사본으로 실제 AWS를 조회했다. 계획은 **9 to import, 0 to add, 0 to change, 0 to destroy**였고, 기존 EC2 3개와 peering 경로 5개가 보존됐다. `validate`, 네트워크 mock plan 테스트, 포맷 검사를 통과했다. 편입 후 상태를 모사한 로컬 fixture의 destroy 계획은 네트워크 9개 모두의 `prevent_destroy`로 차단됐다. 실제 apply나 원격 state 변경은 실행하지 않았다.

```sh
terraform -chdir=terraform/dev init -input=false -lockfile=readonly
terraform -chdir=terraform/dev validate
terraform -chdir=terraform/dev plan -input=false -lock-timeout=60s
```

`versions.tf`와 lockfile은 실행 루트의 Terraform/provider 버전을 고정한다. child는 기존 파일에 `hashicorp/aws` 요구사항을 선언하고 루트 provider 설정을 상속한다. state·plan은 저장소 밖 권한 제한 경로에 보관한다.
