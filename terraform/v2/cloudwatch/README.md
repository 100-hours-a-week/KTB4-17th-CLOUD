# V2 모니터링·CloudWatch 로그 전달 인프라

독립 root이며 backend `prod/cloudwatch-loki/terraform.tfstate`를 유지한다. `module.monitoring`은 V2 EC2·SG를, `module.cloudwatch_loki`는 로그 전달 IAM·SG·로그 보관·선택적 SQS·호출 권한·retry 설정(1시간/2회)·세 ECS 로그 구독을 소유한다. EC2는 기존 private AMI와 데이터로 부팅하며 EIP 없이 일반 public IPv4를 자동 할당한다. EC2 삭제 보호는 유지한다.

Lambda 함수 전체 lifecycle과 ZIP·runtime·환경·relabel·VPC/DLQ 부착은 외부 배포가 관리한다. Terraform은 함수 코드·환경을 조회하거나 더미 함수를 생성하지 않는다. 기존 함수 이름 `star23-prod-cloudwatch-loki`와 partition/region/account로 만든 ARN을 연결에 사용한다. 실행 역할과 SG는 Terraform 출력 계약을 따른다.

## 완료한 이전

2026-11-09 V1 데이터의 최종 동기화와 과거 데이터 보존을 확인하고 Grafana·Prometheus·Loki 및 외부 Lambda를 V2로 전환했다. Lambda 코드와 목적지 외 환경은 유지했다. 실제 CloudWatch 구독 로그 도착, 누락 가능 구간의 원본 로그 재전달, V2 메트릭 두 주기, HTTPS와 Grafana datasource 연결을 확인했다. V1 사설 scrape 대상은 새 수집 설정에서 제외했다.

사용자가 Grafana A 레코드를 새 주소로 변경한 뒤 기존 EC2를 종료하지 않고 중지했다. 기존 볼륨과 private 복구 AMI는 보존한다. V1↔V2 피어링·12개 경로·10개 교차 SG 규칙과 옛 Lambda SG는 제거했다. 새 Loki 수신 규칙은 `monitoring/security.tf`, Lambda SG·송신 규칙은 `forwarder/security.tf`, BE·WS 메트릭 수신은 각 서비스의 `security.tf`에 둔다. 이미 적용한 일회성 주소 이동 선언은 제거했으며 자원 ID를 유지했다.

## 운영 입력과 확인

입력은 저장소 밖에서 관리하는 로컬 파일을 명시적 `-var-file`로 전달한다. 필수 입력은 `monitoring_ami_id`, `monitoring_ssh_cidrs`, `monitoring_grafana_admin_cidrs`다. V2 VPC/subnet ID와 queue·구독 스위치도 명시한다. 관리자 CIDR을 생략하거나 빈 목록으로 대체하면 기존 접근 규칙을 없앨 수 있으므로 운영 파일을 명시한다. 실제 값은 README·Git에 기록하지 않는다.

저장소 루트에서 실행하며, 아래 경로는 실제 입력 파일의 절대 경로로 바꾼다.

```sh
terraform -chdir=terraform/v2/cloudwatch init -input=false -lockfile=readonly
terraform -chdir=terraform/v2/cloudwatch validate
terraform -chdir=terraform/v2/cloudwatch plan -input=false -lock-timeout=60s -var-file=/absolute/path/to/cloudwatch.tfvars.json
terraform -chdir=terraform/v2/cloudwatch output -json monitoring
```

`monitoring.security_group_id` 출력은 V2 루트의 `monitoring_security_group_id` 입력으로 전달해 BE·WS 메트릭 수신과 연결한다. 두 backend는 각각 잠그고 계획을 검토한다. 이관 시 모니터링 전체 계획은 무변경이었으며 V2 전체 계획의 기존 차이 6건은 적용하지 않았다.

public IPv4는 고정되지 않는다. 재시작 등으로 주소가 바뀌면 출력 확인 후 DNS를 갱신한다. 복구 시에는 보존 원본·AMI와 private 기록을 확인하고 수집기·Grafana를 두 곳에서 동시에 쓰지 않는다. 호스트·이미지 변경과 데이터 복구는 별도 계획으로 검토한다. 프로그램 설치·Compose·대시보드·수집 설정·실제 데이터는 이 저장소의 Terraform 관리 범위 밖이다.

## 새로운 환경의 bootstrap

1. V2 네트워크와 ECS 로그 그룹, EC2 key pair 및 `star23-monitoring-metrics` instance profile을 먼저 준비한다. 필요한 프로그램이 포함된 private AMI와 명시적 관리자 CIDR을 전달하고 `enable_function_connections=false`로 모니터링·전달 인프라를 생성한다. V2는 모니터링 SG 생성 전 `monitoring_security_group_id=null`, 이후 실제 출력 ID로 연결한다.
2. 외부 운영이 호스트의 수집기·Grafana·Loki와 데이터를 준비한다. `deployment_infrastructure` 출력의 함수 이름/ARN·execution role·V2 subnet/SG·로그·DLQ 계약에 따라 외부 배포가 Lambda를 만든다. Loki endpoint·환경·동시성·코드 버전은 배포 설정에서 결정한다.
3. 외부 함수 준비 후 `enable_function_connections=true`로 호출 권한·retry·구독을 연결한다. 기존 운영 환경에서 이 플래그를 false로 바꾸면 연결 삭제 계획이므로 일시 중단용으로 사용하지 않는다. source log groups `/ecs/star23/prod/{be,ws,ai}`는 ECS 소유로 유지한다.

선택적 failure queue 기본값은 false, 함수 자체 로그 보관은 30일이다. `grafana_logql`은 조회 도움말이며 Lambda 환경을 설정하지 않는다. 상세 경계는 [루트 README](../../../README.md)를 따른다.
