# 개발 인프라

독립 실행 루트이며 backend는 `dev/terraform.tfstate`다. EC2 3개와 기존 V1 네트워크를 관리한다. SG·EIP·IAM은 외부 소유로 유지한다. V2와의 피어링 및 교차 VPC 접근 규칙은 제거했다. 운영 루트와 합쳐 실행하지 않는다.

## V1 네트워크 소유권

`network`는 기존 자원을 조회하는 `data` 대신 `resource`로 관리한다. 2026-11-09 VPC 1개, IGW 1개, 서브넷 2개, public/default 라우팅 테이블 2개, 인터넷 기본 경로 1개, 서브넷 연결 2개의 원격 state 편입을 완료했다. 실제 자원을 생성·수정·삭제하지 않았으며 기존 ID를 유지했다. 일회성 import 선언은 제거했다.

DNS hostnames 비활성화, 서브넷의 public IP 자동 할당 비활성화, 기존 CIDR·AZ·태그를 실제 AWS와 동일하게 유지한다. EC2가 참조하던 서브넷 map의 키와 ID도 유지한다. `network` 출력은 관리하는 VPC·서브넷·라우팅 테이블·IGW ID를 제공한다.

편입 전 bucket의 여섯 state에서 중복 소유권이 없는지 조사했다. 이후 운영 모니터링을 V2로 이전하고 양방향 피어링 경로를 모두 제거했다. 이 모듈은 inline `route`나 `route = []`를 선언하지 않고 인터넷 기본 경로만 별도 `aws_route`로 관리하므로 외부에서 관리하는 경로를 덮어쓰지 않는다. AWS가 자동 생성한 main/default 테이블은 `aws_default_route_table`로 관리하며 직접 삭제하지 않는다.

운영 모니터링과 로그 전달 Lambda는 V2로 이전했다. V1에는 개발 EC2·GPU와 중지된 기존 모니터링 복구 원본이 남아 있다. 복구 AMI와 원본 볼륨도 보존했다. VPC·IGW·서브넷·테이블·인터넷 경로·연결의 `prevent_destroy`는 유지하므로 **V1 전체 destroy는 삭제 보호로 차단된다.** V1을 철거하려면 남은 소비자와 외부 SG·EIP·IAM 범위를 별도로 확인해야 한다.

편입 전 계획은 **9 to import, 0 to add, 0 to change, 0 to destroy**였고, 당시 기존 EC2 3개와 피어링 경로를 보존했다. 피어링 경로는 이후 V2 독립 이전을 마친 뒤 제거했다. 검토한 계획을 격리된 로컬 state에 반영한 뒤, 백업·잠금·원본 version 확인을 거쳐 원격 dev state에 기록했다. 네트워크 9개와 EC2 3개를 다시 읽어 검증했다. 네트워크 9개 모두의 `prevent_destroy`가 로컬 destroy 계획을 차단하는 것도 확인했다.

```sh
terraform -chdir=terraform/v1 init -input=false -lockfile=readonly
terraform -chdir=terraform/v1 validate
terraform -chdir=terraform/v1 plan -input=false -lock-timeout=60s
```

`versions.tf`와 lockfile은 실행 루트의 Terraform/provider 버전을 고정한다. child는 기존 파일에 `hashicorp/aws` 요구사항을 선언하고 루트 provider 설정을 상속한다. state·plan은 저장소 밖 권한 제한 경로에 보관한다.
