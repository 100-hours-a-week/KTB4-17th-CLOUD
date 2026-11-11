# V1 인프라

독립 실행 루트이며 backend는 `dev/terraform.tfstate`다. 앱·Kafka/Redis·DB용 EC2 3개와 V1 네트워크를 관리한다. SG·EIP·IAM은 외부 소유로 참조한다. V2와의 피어링이나 교차 VPC 접근 규칙은 없다.

`network`는 VPC·IGW·서브넷 2개·public/default 라우팅 테이블·인터넷 기본 경로·서브넷 연결을 관리한다. EC2는 이 모듈의 서브넷 ID를 참조한다. 라우팅 테이블의 모든 경로를 덮어쓰지 않고 인터넷 기본 경로만 별도 `aws_route`로 관리한다.

V1 VPC에는 이 루트 밖에서 관리하는 GPU와 중지된 기존 모니터링 복구 원본도 남아 있다. 복구 AMI와 원본 볼륨도 보존한다. 네트워크의 `prevent_destroy`로 **V1 전체 destroy는 차단된다.** 철거하려면 남은 EC2와 외부 SG·EIP·IAM의 의존성을 먼저 확인해야 한다.

```sh
terraform -chdir=terraform/v1 init -input=false -lockfile=readonly
terraform -chdir=terraform/v1 validate
terraform -chdir=terraform/v1 plan -input=false -lock-timeout=60s
```
