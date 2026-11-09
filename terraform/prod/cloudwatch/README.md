# CloudWatch 로그 전달 인프라

독립 root이며 backend `prod/cloudwatch-loki/terraform.tfstate`, `module.cloudwatch_loki`, 기존 리소스 이름을 유지한다. prod ECS root와 별도로 검토한다. 이번 변경은 이관 선언만 준비하며 운영 함수/배포/상태를 변경하지 않는다.

Terraform은 IAM·SG(기존 Loki TCP 3100 접근)·로그 보관·선택적 SQS·Lambda 호출 권한·retry 설정(1시간/2회)·세 ECS 로그 구독만 관리한다. 함수 전체 lifecycle과 ZIP/버전/runtime/환경/relabel/VPC·DLQ 부착은 외부 배포가 관리한다. `fetch-package.sh`와 ZIP 고정값은 제거했다. 함수는 `removed`/`destroy=false`로 비파괴 이관하며, 코드 없는 함수나 더미 ZIP은 만들지 않는다.

기존 환경에서는 `enable_function_connections=true`(기본값), 기존 Loki 참조와 `enable_failure_queue` 설정을 유지한다. 외부 함수 참조는 기존 이름 `star23-prod-cloudwatch-loki`와 현재 partition/region/account로 만든 ARN이다. 함수 코드/환경을 읽지 않으며 subscriptions·권한은 이 ARN/이름으로 연결한다. 비동기 호출 설정은 `moved`로 기존 주소를 `[0]`에 연결한다.

새 환경 순서:

1. 새 backend, `loki_instance_id`, `loki_security_group_id`, queue 선택을 준비하고 `enable_function_connections=false`로 인프라를 먼저 만든다. ECS 로그 그룹도 이미 있어야 한다. 아직 함수 호출/구독 리소스는 만들지 않는다.
2. `deployment_infrastructure` 출력의 정확한 함수 이름/ARN, execution role, subnet/SG, 로그 그룹과 DLQ ARN을 외부 배포에 전달한다. 외부 배포가 실제 Promtail 함수와 모든 프로그램 설정을 생성한다. Loki endpoint·labels/relabel·code version·환경·동시성은 배포 설정에서 결정한다. 같은 이름·VPC/SG/역할·DLQ 계약을 사용하며 기존 Loki 접근 외 네트워크를 이 PR에서 추가하지 않는다.
3. 외부 함수 준비 뒤 `enable_function_connections=true`로 권한·retry·구독을 연결한다. 기존 환경에서 이 플래그를 false로 전환하면 연결 삭제 계획이므로 전환 절차로 사용하지 않는다. source log groups는 `/ecs/star23/prod/{be,ws,ai}`를 유지하고 연결 이후 로그를 전달한다.

```sh
terraform -chdir=terraform/prod/cloudwatch init -input=false -lockfile=readonly
terraform -chdir=terraform/prod/cloudwatch validate
```

Loki 호스트와 원본 ECS 로그 그룹은 외부 참조다. 선택적 failure queue 기본값은 false, 자체 로그 보관은 30일이다. `grafana_logql` 출력은 기존 대시보드 조회 도움말일 뿐 Lambda 환경을 설정하지 않는다. 상세 소유권/검증/운영 plan 미수행 제한은 [루트 README](../../../README.md)를 따른다.
