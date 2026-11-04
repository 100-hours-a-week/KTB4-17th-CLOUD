# CloudWatch 로그 전달

독립 실행 루트다. `cloudwatch/`라는 소스 디렉터리 이름과 무관하게 기존 backend `prod/cloudwatch-loki/terraform.tfstate`, `module.cloudwatch_loki`, 리소스 이름은 유지한다.

ECS의 기존 CloudWatch 로그 그룹 → Lambda Promtail → 기존 Loki로 전달한다. 이 연결의 Lambda·IAM·SG 규칙·로그 구독은 IaC 관리 대상이다. 기존 Loki 호스트 전체와 원본 ECS 로그 그룹을 이 루트에서 관리하지 않는다. 목적지 이름을 디렉터리명에 넣을 필요는 없다.

```sh
terraform/prod/cloudwatch/fetch-package.sh
terraform -chdir=terraform/prod/cloudwatch init -input=false -lockfile=readonly
terraform -chdir=terraform/prod/cloudwatch validate
terraform -chdir=terraform/prod/cloudwatch plan -input=false -lock-timeout=60s
```

helper는 공식 v1.0.1 ZIP의 고정 SHA256을 확인한다. `dist/lambda-promtail-v1.0.1.zip`과 상대 경로는 유지하며 ZIP은 Git에서 제외한다. provider lockfile은 커밋한다.

외부 Loki EC2/SG는 `loki_instance_id`, `loki_security_group_id`로 지정한다. `enable_failure_queue`는 기본 false다. 전달 Lambda는 Loki 3100으로 통신하며 새 NAT/공개 포트를 만들지 않는다. 계정 quota 때문에 예약 동시성은 -1이며 자체 로그는 30일 보관한다. 전달 실패는 1시간/2회 재시도한다.

Grafana Explore: `{environment="prod", source="cloudwatch"}`. 원본 로그는 `/ecs/star23/prod/be`, `/ecs/star23/prod/ws`, `/ecs/star23/prod/ai`에 남는다. 구독은 연결 이후 도착한 로그를 전달한다.
