# 운영 ECS 로그 → Loki

BE·WS·AI의 기존 CloudWatch 로그 그룹을 공식 Grafana Lambda Promtail v1.0.1로 구독해 기존 Loki에 보낸다. ECS 태스크 정의와 애플리케이션 코드는 수정하지 않는다.

`ECS → CloudWatch → Lambda (기존 운영 VPC) → Loki 10.0.1.88:3100`

## 소스 복원과 읽기 전용 검증 (#11)

이 디렉터리는 독립 Terraform 루트다. 기존 S3 백엔드
`prod/cloudwatch-loki/terraform.tfstate`를 그대로 사용한다. 상위 운영 루트
`prod/terraform.tfstate`에 이 모듈을 추가하지 않는다.

저장소 루트에서 실행한다. plan과 JSON은 저장소 밖의 권한 제한 디렉터리에 둔다.

```bash
terraform/prod/cloudwatch-loki/fetch-package.sh
terraform -chdir=terraform/prod/cloudwatch-loki init -input=false
terraform fmt -check -recursive terraform
terraform -chdir=terraform/prod/cloudwatch-loki validate
terraform -chdir=terraform/prod/cloudwatch-loki plan -lock=false -input=false
```

공식 ZIP의 SHA256을 다운로드 스크립트에서 검증한다. provider 선택은
`.terraform.lock.hcl`에 기록한다. ZIP·입력·state·raw plan은 커밋하지 않는다.
이슈 #11의 작업은 소스 복원과 읽기 전용 검증까지다. 전체 검증 결과와 소유권은
[운영 기준선 기록](../../../docs/terraform-production-baseline.md)을 참조한다.

## 조회

Grafana Explore에서 기존 Loki 데이터 소스를 선택한다.

```logql
{environment="prod", source="cloudwatch"}
{environment="prod", service="spring"}
{environment="prod", service="ws"}
{environment="prod", service="ai"}
```

`ecs_service`, `cloudwatch_log_group`, `cluster` 라벨도 추가된다. task ID와 log stream은 라벨로 사용하지 않는다. 공식 v1.0.1의 라벨 정렬 누락을 피하기 위해 입력 라벨은 CloudWatch 그룹 하나만 남기고 고정 라벨을 relabel 규칙으로 추가한다. subscription은 연결 후 도착한 로그부터 전달한다.

## 운영 범위

- 원본 로그 그룹: `/ecs/star23/prod/be`, `/ecs/star23/prod/ws`, `/ecs/star23/prod/ai`.
- Lambda는 로컬 Loki 3100 포트에만 통신한다. 새 NAT나 공개 수신 포트를 만들지 않는다.
- 실행 역할은 자체 Lambda 로그 쓰기와 VPC ENI 관리에 한정한다. 실패 큐를 활성화하면 해당 큐 전송 권한만 추가한다. 애플리케이션 시크릿과 원본 CloudWatch 로그 읽기 권한은 부여하지 않는다.
- 원문 로그를 전달기 자체 CloudWatch 로그에 중복 출력하지 않는다.
- Lambda 자체 로그는 30일 보관하고, 비동기 전달은 최대 1시간 동안 2회 재시도한다. 원본 로그는 기존 ECS CloudWatch 그룹에 남는다.
- 현재 운영 루트의 `enable_failure_queue=false`를 유지한다. 실패 큐 추가와 IAM 변경은 이 복원 범위에 포함하지 않는다.
- 계정 동시 실행 한도가 10이므로 함수 전용 예약은 사용하지 않는다.
- 전달기와 구독은 기존 운영 리소스다. Loki·원본 ECS 로그 그룹은 이 루트에서 새로 관리하지 않는다.
