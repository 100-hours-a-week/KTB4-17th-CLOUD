# V2 모니터링·로그 전달 인프라

독립 backend `prod/cloudwatch-loki/terraform.tfstate`를 사용한다. `module.monitoring`은 V2 EC2·SG를, `module.cloudwatch_loki`는 로그 전달 IAM·SG·로그 그룹·선택적 SQS·호출 권한·재시도 설정·ECS 로그 구독을 관리한다.

EC2는 private AMI로 부팅하며 일반 public IPv4를 할당한다. 삭제 보호를 유지하고, 중지 중 공인 IP가 반납되어도 인스턴스 교체를 계획하지 않는다. 중지 후 시작하거나 인스턴스를 다시 만들면 공인 주소가 바뀔 수 있으므로 출력 확인 후 Grafana DNS를 갱신한다.

Lambda 함수 `star23-prod-cloudwatch-loki`의 생성·코드·runtime·환경·VPC/DLQ 부착은 외부 배포가 관리한다. 서버 프로그램·Compose·대시보드·수집 설정·실제 데이터도 외부 운영 범위다.

## 입력과 실행

입력 파일은 저장소 밖에서 관리한다. `monitoring_ami_id`, `monitoring_ssh_cidrs`, `monitoring_grafana_admin_cidrs`와 V2 VPC/subnet ID를 전달한다. 관리자 CIDR을 비우면 기존 접근 규칙의 삭제 계획이 발생하므로 운영 값을 명시한다. 아래 경로는 실제 입력 파일의 절대 경로로 바꾼다.

```sh
terraform -chdir=terraform/v2/cloudwatch init -input=false -lockfile=readonly
terraform -chdir=terraform/v2/cloudwatch validate
terraform -chdir=terraform/v2/cloudwatch plan -input=false -lock-timeout=60s -var-file=/absolute/path/to/cloudwatch.tfvars.json
terraform -chdir=terraform/v2/cloudwatch output -json monitoring
```

`monitoring.security_group_id` 출력은 V2 루트의 `monitoring_security_group_id` 입력으로 전달한다. Loki 수신 규칙은 `monitoring/security.tf`, Lambda SG·송신 규칙은 `forwarder/security.tf`, BE·WS 메트릭 수신은 각 서비스의 `security.tf`에서 관리한다.

## 새 환경 구성 순서

1. V2 네트워크·ECS 로그 그룹·EC2 key pair·`star23-monitoring-metrics` instance profile과 private AMI를 준비한다. `enable_function_connections=false`로 모니터링·전달 기반을 생성한다. V2의 `monitoring_security_group_id`에는 생성된 SG ID를 전달한다.
2. 외부 운영이 모니터링 프로그램과 데이터를 준비한다. 외부 배포는 `deployment_infrastructure` 출력의 함수 이름·ARN·역할·subnet·SG·로그·DLQ 정보로 Lambda를 생성한다.
3. 함수 준비 후 `enable_function_connections=true`로 호출 권한·재시도·구독을 연결한다. 기존 운영 환경에서는 true를 유지한다.

ECS 원본 로그 그룹 `/ecs/star23/prod/{be,ws,ai}`는 ECS 루트가 관리한다. 함수 로그 보관은 30일, 비동기 재시도는 최대 1시간/2회이며 선택적 failure queue의 기본값은 false다.
