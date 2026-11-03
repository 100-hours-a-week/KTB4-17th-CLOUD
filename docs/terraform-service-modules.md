# #5 서비스 중심 Terraform — 코드/리뷰 단계

이 변경은 운영 ECS의 소유권을 서비스 단위로 재구성한다. **실제 원격 state 정합성
반영은 미실행**이며, #5는 열어 둔다. PR은 main 대상 Draft로 유지하며 merge하지 않는다.
기준 커밋은 #13을 merge한 `d6da1e92d26fdf0c4105586c277c7f1395fc29c9`다.
기존 기준선의 다섯 커밋을 보존하고 #5 커밋만 추가한다.

## 환경 실행 경로와 단일 소유권

| 환경 / 성격 | 실행 루트 | 기존 backend key | 단일 소유자와 범위 |
| --- | --- | --- | --- |
| prod V2 ECS | `terraform` | `prod/terraform.tfstate` | `module.cluster`, `module.be`, `module.ws`, `module.ai`, shared network/ALB/database/storage/CDN, 루트 SG 연결 |
| prod 로그 전송 | `terraform/cloudwatch-loki` | `prod/cloudwatch-loki/terraform.tfstate` | 기존 Lambda/IAM/전용 SG/구독만; ECS 로그 그룹은 data 조회 |
| dev V1 EC2 | 현재 관리 root 없음, inventory-only | dev EC2 소유 backend 미확정 | 기존 EC2/DB/SG 자체의 신규 편입은 보류; prod가 이미 소유한 peering·추가 route/SG rule만 보존 |
| 공유 객체 | 기존 prod root 안의 명시적 소유자 | prod key 유지 | network: VPC/subnets/NAT/routes·ALB/DB SG; database: MySQL·PostgreSQL; storage: ECR/S3; cdn: 공유 CloudFront |
| 공유 앱 Secret | `module.be` | prod key 유지 | 기존 Secret/version·SSM은 한 곳만 생성; WS/AI에는 필요한 ARN 참조 전달 |

backend bucket은 두 root 모두 `star23-tfstate-975779326240`, region은
`ap-northeast-2`다. root 디렉터리 이동이나 state 분할은 하지 않는다.
`terraform`은 명시적인 prod entrypoint이며 environment 입력만 dev로 바꿔 실행하지 않는다.
retired staging은 dev로 이름을 바꾸거나 재생성하지 않는다. 공유 CloudFront의 기존
`dev`·`stag` alias/Function 이름은 ECS 환경 복원과 무관하며 그대로 유지한다.

## 서비스 설계

- `modules/ecs/cluster`: 공유 cluster/namespace.
- `modules/ecs/services/be`: BE task/service, SG/egress, 기존 IAM, logs, SSM 및 공유 Secret/version 소유.
- `modules/ecs/services/ws`: WS task/service, S3 정책, config/secret 참조와 BE ARN 재사용 선택; 전용 runtime 인스턴스 소유.
- `modules/ecs/services/ai`: AI task/service, config/secret 참조와 CI 리비전용 기존 추가 secret 권한; 전용 runtime 인스턴스 소유.
- `modules/ecs/runtime`: WS·AI의 같은 IAM/log/SG 구현만 재사용한다. task/service를 3벌 복사하거나 한 리소스 wrapper를 쌓지 않는다.
- `connections.tf`: 서비스/ALB/DB 간 SG edge를 단독 소유한다. 서비스 모듈 간 역참조와 network→service 순환을 만들지 않는다.

root가 cluster ID/namespace ARN, 선택한 subnet IDs, ALB target group ARN,
ECR/S3 ARN과 config 참조를 명시적으로 전달한다. shared network가 subnet을 생성하고
서비스가 배치 입력을 선택한다. BE의 기존 AWS 역할 이름은 바꾸지 않는다.
세 서비스 모두 CI/CD의 실제 task revision 소유권(`ignore_changes`)을 유지한다.
WS SG/egress와 연결 규칙은 기존 모델처럼 WS enable 여부와 별개로 소유하며,
WS task/service/IAM/log만 enable 조건을 따른다.

## 검증된 읽기 전용 결과

2026-11-03, account `975779326240`, IAM user `noel`, Seoul region으로 다시 조회했다.
기존 private 입력을 재사용하고, state가 가리키는 실제 Secret version을 다시 읽어
권한 제한 파일의 ephemeral 입력으로만 전달했다. dummy secret이나 refresh 생략,
`-target`을 사용하지 않았다. provider는 기존 lock의 AWS 6.71.0이다.

| 전체 refresh plan | complete | errored | create | update | delete | replace | import | forget | 주소 이동 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| private ONE-OFF 주입 prod 사본 | true | false | 0 | 0 | 0 | 0 | 7 | 2 | 94 |
| 기존 별도 Loki root | true | false | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

위 prod 결과는 **state-only 제안이 포함된 migration plan**이며 실제 state를 옮긴
결과나 최종 steady-source no-op 결과가 아니다. 실제 정합성 반영 전에는 tracked
steady source만으로 prod plan을 성공이라고 주장할 수 없다.

`terraform fmt -check -recursive terraform`, 두 runnable root의 `terraform validate`,
`python3 -m unittest discover -s tests -v` (12개)가 통과했다. 테스트는 모든 AWS write와
양방향 replacement, 불완전/errored/deferred plan, 임의/누락/ID 불일치 state 동작,
중복 주소, private 값 비출력, backend 경계, CI revision 소유권과 migration 블록 부재를 검사한다.
`check_readonly_plan.py`는 manifest 없이는 state 동작도 허용하지 않으며, migration에서는
정확한 imports/forget/moves 전체 집합이 일치해야 한다.

운영과 별도 Loki 및 세 staging state를 읽어 import 대상의 중복 managed 소유권이
없음을 재확인했다. prod serial 29, Loki serial 4이며, 검증 전후 state bytes와
lineage/serial이 동일함을 확인했다. 나머지 세 state도 동일성을 확인했다.
이 실행은 AWS read API, backend 초기화, `-lock=false` plan만 사용한다.
apply/destroy/import/state mv/rm/push, AWS·DNS·IAM 쓰기, merge, EIP 정리를 하지 않는다.
원본 dirty 저장소와 이전 worktree는 변경하지 않는다.

prod의 두 RDS, ALB HTTP/HTTPS·priority-1 chat 경로, WS/AI 통신과 DB 규칙,
CloudFront의 모든 alias/origin/behavior/Function 연결을 그대로 보존한다.
전체 plan의 각 managed 리소스에서 ID와 no-op을 대조했고, 서비스 실제 배포 revision도
추가 읽기 조회로 확인했다. Loki의 source와 backend는 이 PR에서 변경하지 않는다.

## 재검증과 비공개 ONE-OFF 보관

권한 제한 저장소 밖 sibling `service-modules-private/`에 원격 snapshot, manifest,
`production/ONE-OFF.tf`, full binary/JSON plan, 입력과 API 증거를 보관한다.
원본 과거 reconciliation 선언도 그곳에만 보관한다. tracked `.tf` 전체에는
`import`/`moved`/`removed` 블록이 0개다. 영구 migration 디렉터리를 만들지 않는다.
raw state/plan/secret/tfvars/ZIP/.terraform/.ouroboros는 commit/PR에 올리지 않는다.

운영자는 private 입력과 artifact 경로를 환경 변수로 지정한 뒤 다음과 같이
검증할 수 있다. `MIGRATION_COPY`는 제출 소스와 동일하고 이 문서의 정확한 주소만
ONE-OFF로 추가한 private 사본이며, 원래 prod backend identity를 그대로 사용한다.

```bash
umask 077
terraform fmt -check -recursive terraform
terraform -chdir=terraform init -input=false -lockfile=readonly
terraform -chdir=terraform validate
terraform -chdir=terraform/cloudwatch-loki init -input=false -lockfile=readonly
terraform/cloudwatch-loki/fetch-package.sh
terraform -chdir=terraform/cloudwatch-loki validate
python3 -m unittest discover -s tests -v
terraform -chdir="$MIGRATION_COPY" init -input=false -lockfile=readonly
terraform -chdir="$MIGRATION_COPY" validate
terraform -chdir="$MIGRATION_COPY" plan -lock=false -input=false \
  -var-file="$PROD_INPUTS" -var-file="$RUNTIME_INPUTS" \
  -var-file="$CURRENT_INPUTS" -var-file="$SECRET_RUNTIME_INPUTS" \
  -out="$PRIVATE_ARTIFACTS/production.tfplan" > "$PRIVATE_ARTIFACTS/production-plan.log" 2>&1
terraform -chdir="$MIGRATION_COPY" show -json "$PRIVATE_ARTIFACTS/production.tfplan" > "$PRIVATE_ARTIFACTS/production-plan.json"
python3 scripts/check_readonly_plan.py "$PRIVATE_ARTIFACTS/production-plan.json" --manifest "$PRIVATE_ARTIFACTS/manifest.json"
terraform -chdir=terraform/cloudwatch-loki plan -lock=false -input=false \
  -out="$PRIVATE_ARTIFACTS/loki.tfplan" > "$PRIVATE_ARTIFACTS/loki-plan.log" 2>&1
terraform -chdir=terraform/cloudwatch-loki show -json "$PRIVATE_ARTIFACTS/loki.tfplan" > "$PRIVATE_ARTIFACTS/loki-plan.json"
python3 scripts/check_readonly_plan.py "$PRIVATE_ARTIFACTS/loki-plan.json"
```

private plan은 민감한 산출물이므로 review에는 아래 주소·ID와 집계만 사용한다.
실행 전 backend lineage/serial과 live ownership이 달라지면 제안을 재작성하고 전체
검증을 반복한다. Route53 목록 권한은 확대하지 않으며 검증을 위해 AWS를 수정하지 않는다.

## 남은 별도 승인 단계와 범위 밖 작업

1. 이 Draft PR의 코드·아래 정확한 94 move/7 import/2 forget 제안을 검토한다.
2. **별도 state-only 실행 승인** 후에만 최신 state/live ownership과 전체 plan을 다시
   확인하고, 이 정확한 동작만 수행하는 별도 state reconciliation 절차를 진행한다.
   현재 저장한 plan을 시간 경과 후 바로 실행하는 승인이 아니다. AWS write가 한 건이라도
   있거나 주소/ID가 다르면 중단한다. 이 코드 단계에는 실행 승인이 없다.
3. 승인된 정합성 반영이 끝나면 private ONE-OFF 선언을 active 사본에서 제거하고,
   최종 tracked steady source만으로 전체 refresh plan을 실행해 import/forget/move 없이
   0 create/update/delete/replace를 확인한다. 별도 Loki도 다시 검증한다.
4. 위 결과가 확인될 때까지 #5 OPEN / PR DRAFT 유지. merge나 issue 자동 종료 문구를 쓰지 않는다.

후속: dev EC2·연관 리소스 inventory와 기존 state 중복 소유권 조사, dev backend/root
확정 및 별도 adoption 승인, 공유 리소스의 cross-backend 이동 필요성 검토는 미완료다.
이 PR은 dev EC2를 새로 관리하거나 생성하지 않는다. retired staging 복원, backend 간
migration/state 분할, #12의 EIP 정리도 수행하지 않는다.

## 정확한 미실행 import / forget 제안

| 동작 | 주소 | 정확한 기존 ID |
| --- | --- | --- |
| import 제안 | `module.cdn.aws_cloudfront_distribution.fe` | `E3LYSMQO2T1UT` |
| import 제안 | `module.storage.aws_ecr_repository.be` | `star23/be` |
| import 제안 | `module.storage.aws_ecr_repository.ai` | `star23/ai` |
| import 제안 | `module.storage.aws_s3_bucket.fe` | `star23-s3-deploy-bucket-975779326240-ap-northeast-2-an` |
| import 제안 | `module.storage.aws_s3_bucket.image` | `star23-images` |
| import 제안 | `module.alb.aws_lb_listener_rule.chat_routes` | `arn:aws:elasticloadbalancing:ap-northeast-2:975779326240:listener-rule/app/star23-alb/1ca5051586e3c967/7486e2341aeaa359/a1bcba60b2a96fb8` |
| import 제안 | `aws_vpc_security_group_ingress_rule.ai_from_ws` | `sgr-0030fb498843e37b8` |
| forget 제안 (AWS 삭제 아님) | `module.alb.aws_lb_listener_rule.ws` | `arn:aws:elasticloadbalancing:ap-northeast-2:975779326240:listener-rule/app/star23-alb/1ca5051586e3c967/7486e2341aeaa359/f8cd5cf50f103400` |
| forget 제안 (AWS 삭제 아님) | `module.alb.aws_lb_listener_rule.ws_ai_practice` | `arn:aws:elasticloadbalancing:ap-northeast-2:975779326240:listener-rule/app/star23-alb/1ca5051586e3c967/7486e2341aeaa359/0abaf0678dd25457` |

두 forget은 이미 존재하지 않는 과거 ALB 규칙의 **state 기록만 해제**하는 제안이다.
새 live priority-1 규칙의 ID로 과거 주소를 덮어쓰지 않는다. 역사적 root 주소는 현재
다섯 backend의 실제 소유권에 맞는 active 94개 move로 축약했으며, 미사용 이력은
private archive에만 남긴다. 아래 각 행은 한 기존 객체를 정확히 한 최종 주소로 보존한다.

## 정확한 주소 이동 / 기존 ID 유지 표 (94건)

| 기존 주소 | 최종 주소 | 유지하는 기존 ID |
| --- | --- | --- |
| `module.ecs.aws_cloudwatch_log_group.service["ai"]` | `module.ai.module.runtime.aws_cloudwatch_log_group.service[0]` | `/ecs/star23/prod/ai` |
| `module.ecs.aws_cloudwatch_log_group.service["be"]` | `module.be.aws_cloudwatch_log_group.service` | `/ecs/star23/prod/be` |
| `module.ecs.aws_cloudwatch_log_group.service["ws"]` | `module.ws.module.runtime.aws_cloudwatch_log_group.service[0]` | `/ecs/star23/prod/ws` |
| `module.ecs.aws_ecs_cluster.main` | `module.cluster.aws_ecs_cluster.main` | `arn:aws:ecs:ap-northeast-2:975779326240:cluster/star23-ecs-cluster` |
| `module.ecs.aws_ecs_service.ai` | `module.ai.aws_ecs_service.ai` | `arn:aws:ecs:ap-northeast-2:975779326240:service/star23-ecs-cluster/star23-ai-service` |
| `module.ecs.aws_ecs_service.be` | `module.be.aws_ecs_service.be` | `arn:aws:ecs:ap-northeast-2:975779326240:service/star23-ecs-cluster/star23-be-service` |
| `module.ecs.aws_ecs_service.ws[0]` | `module.ws.aws_ecs_service.ws[0]` | `arn:aws:ecs:ap-northeast-2:975779326240:service/star23-ecs-cluster/star23-ws-service` |
| `module.ecs.aws_ecs_task_definition.ai` | `module.ai.aws_ecs_task_definition.ai` | `star23-ai` |
| `module.ecs.aws_ecs_task_definition.be` | `module.be.aws_ecs_task_definition.be` | `star23-be` |
| `module.ecs.aws_ecs_task_definition.ws[0]` | `module.ws.aws_ecs_task_definition.ws[0]` | `star23-ws` |
| `module.ecs.aws_iam_role.ecs_execution` | `module.be.aws_iam_role.ecs_execution` | `star23-ecs-execution-role` |
| `module.ecs.aws_iam_role.ecs_task` | `module.be.aws_iam_role.ecs_task` | `star23-ecs-task-role` |
| `module.ecs.aws_iam_role.service_execution["ai"]` | `module.ai.module.runtime.aws_iam_role.service_execution["ai"]` | `star23-ai-ecs-execution-role` |
| `module.ecs.aws_iam_role.service_execution["ws"]` | `module.ws.module.runtime.aws_iam_role.service_execution["ws"]` | `star23-ws-ecs-execution-role` |
| `module.ecs.aws_iam_role.service_task["ai"]` | `module.ai.module.runtime.aws_iam_role.service_task["ai"]` | `star23-ai-ecs-task-role` |
| `module.ecs.aws_iam_role.service_task["ws"]` | `module.ws.module.runtime.aws_iam_role.service_task["ws"]` | `star23-ws-ecs-task-role` |
| `module.ecs.aws_iam_role_policy.be_s3` | `module.be.aws_iam_role_policy.be_s3` | `star23-ecs-task-role:star23-be-s3` |
| `module.ecs.aws_iam_role_policy.ecs_execution_secrets[0]` | `module.be.aws_iam_role_policy.ecs_execution_secrets[0]` | `star23-ecs-execution-role:star23-ecs-execution-secrets` |
| `module.ecs.aws_iam_role_policy.service_execution_secrets["ai"]` | `module.ai.module.runtime.aws_iam_role_policy.service_execution_secrets["ai"]` | `star23-ai-ecs-execution-role:star23-ai-ecs-execution-secrets` |
| `module.ecs.aws_iam_role_policy.service_execution_secrets["ws"]` | `module.ws.module.runtime.aws_iam_role_policy.service_execution_secrets["ws"]` | `star23-ws-ecs-execution-role:star23-ws-ecs-execution-secrets` |
| `module.ecs.aws_iam_role_policy.ws_s3[0]` | `module.ws.aws_iam_role_policy.ws_s3[0]` | `star23-ws-ecs-task-role:star23-ws-s3` |
| `module.ecs.aws_iam_role_policy_attachment.ecs_execution` | `module.be.aws_iam_role_policy_attachment.ecs_execution` | `star23-ecs-execution-role/arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy` |
| `module.ecs.aws_iam_role_policy_attachment.service_execution["ai"]` | `module.ai.module.runtime.aws_iam_role_policy_attachment.service_execution["ai"]` | `star23-ai-ecs-execution-role/arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy` |
| `module.ecs.aws_iam_role_policy_attachment.service_execution["ws"]` | `module.ws.module.runtime.aws_iam_role_policy_attachment.service_execution["ws"]` | `star23-ws-ecs-execution-role/arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy` |
| `module.ecs.aws_secretsmanager_secret.be` | `module.be.aws_secretsmanager_secret.be` | `arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:star23/prod/be-q1bpe9` |
| `module.ecs.aws_secretsmanager_secret_version.be` | `module.be.aws_secretsmanager_secret_version.be` | `arn:aws:secretsmanager:ap-northeast-2:975779326240:secret:star23/prod/be-q1bpe9|terraform-gZGSWr5TiuTJGHVC7uHS3x3FeJ` |
| `module.ecs.aws_service_discovery_http_namespace.ecs` | `module.cluster.aws_service_discovery_http_namespace.ecs` | `ns-k6pvl6yg5znymjo7` |
| `module.ecs.aws_ssm_parameter.be_config["AI_PERSONA_BASE_URL"]` | `module.be.aws_ssm_parameter.be_config["AI_PERSONA_BASE_URL"]` | `/star23/prod/be/AI_PERSONA_BASE_URL` |
| `module.ecs.aws_ssm_parameter.be_config["AI_PRACTICE_BASE_URL"]` | `module.be.aws_ssm_parameter.be_config["AI_PRACTICE_BASE_URL"]` | `/star23/prod/be/AI_PRACTICE_BASE_URL` |
| `module.ecs.aws_ssm_parameter.be_config["AI_PRACTICE_CONNECT_TIMEOUT_MS"]` | `module.be.aws_ssm_parameter.be_config["AI_PRACTICE_CONNECT_TIMEOUT_MS"]` | `/star23/prod/be/AI_PRACTICE_CONNECT_TIMEOUT_MS` |
| `module.ecs.aws_ssm_parameter.be_config["AI_PRACTICE_DAILY_LIMIT"]` | `module.be.aws_ssm_parameter.be_config["AI_PRACTICE_DAILY_LIMIT"]` | `/star23/prod/be/AI_PRACTICE_DAILY_LIMIT` |
| `module.ecs.aws_ssm_parameter.be_config["AI_PRACTICE_END_SESSION_PATH"]` | `module.be.aws_ssm_parameter.be_config["AI_PRACTICE_END_SESSION_PATH"]` | `/star23/prod/be/AI_PRACTICE_END_SESSION_PATH` |
| `module.ecs.aws_ssm_parameter.be_config["AI_PRACTICE_INITIAL_SESSION_PATH"]` | `module.be.aws_ssm_parameter.be_config["AI_PRACTICE_INITIAL_SESSION_PATH"]` | `/star23/prod/be/AI_PRACTICE_INITIAL_SESSION_PATH` |
| `module.ecs.aws_ssm_parameter.be_config["AI_PRACTICE_MESSAGE_PATH"]` | `module.be.aws_ssm_parameter.be_config["AI_PRACTICE_MESSAGE_PATH"]` | `/star23/prod/be/AI_PRACTICE_MESSAGE_PATH` |
| `module.ecs.aws_ssm_parameter.be_config["AI_PRACTICE_OUTBOX_MAX_FAILURES"]` | `module.be.aws_ssm_parameter.be_config["AI_PRACTICE_OUTBOX_MAX_FAILURES"]` | `/star23/prod/be/AI_PRACTICE_OUTBOX_MAX_FAILURES` |
| `module.ecs.aws_ssm_parameter.be_config["AI_PRACTICE_OUTBOX_PUBLISH_DELAY_MS"]` | `module.be.aws_ssm_parameter.be_config["AI_PRACTICE_OUTBOX_PUBLISH_DELAY_MS"]` | `/star23/prod/be/AI_PRACTICE_OUTBOX_PUBLISH_DELAY_MS` |
| `module.ecs.aws_ssm_parameter.be_config["AI_PRACTICE_READ_TIMEOUT_MS"]` | `module.be.aws_ssm_parameter.be_config["AI_PRACTICE_READ_TIMEOUT_MS"]` | `/star23/prod/be/AI_PRACTICE_READ_TIMEOUT_MS` |
| `module.ecs.aws_ssm_parameter.be_config["AI_PRACTICE_RETRY_PATH"]` | `module.be.aws_ssm_parameter.be_config["AI_PRACTICE_RETRY_PATH"]` | `/star23/prod/be/AI_PRACTICE_RETRY_PATH` |
| `module.ecs.aws_ssm_parameter.be_config["AI_SIMULATION_ASYNC_POOL_SIZE"]` | `module.be.aws_ssm_parameter.be_config["AI_SIMULATION_ASYNC_POOL_SIZE"]` | `/star23/prod/be/AI_SIMULATION_ASYNC_POOL_SIZE` |
| `module.ecs.aws_ssm_parameter.be_config["AI_SIMULATION_ASYNC_QUEUE_CAPACITY"]` | `module.be.aws_ssm_parameter.be_config["AI_SIMULATION_ASYNC_QUEUE_CAPACITY"]` | `/star23/prod/be/AI_SIMULATION_ASYNC_QUEUE_CAPACITY` |
| `module.ecs.aws_ssm_parameter.be_config["AI_SIMULATION_ASYNC_SHUTDOWN_WAIT_SECONDS"]` | `module.be.aws_ssm_parameter.be_config["AI_SIMULATION_ASYNC_SHUTDOWN_WAIT_SECONDS"]` | `/star23/prod/be/AI_SIMULATION_ASYNC_SHUTDOWN_WAIT_SECONDS` |
| `module.ecs.aws_ssm_parameter.be_config["AI_SIMULATION_BASE_URL"]` | `module.be.aws_ssm_parameter.be_config["AI_SIMULATION_BASE_URL"]` | `/star23/prod/be/AI_SIMULATION_BASE_URL` |
| `module.ecs.aws_ssm_parameter.be_config["AI_SIMULATION_CONNECT_TIMEOUT_MS"]` | `module.be.aws_ssm_parameter.be_config["AI_SIMULATION_CONNECT_TIMEOUT_MS"]` | `/star23/prod/be/AI_SIMULATION_CONNECT_TIMEOUT_MS` |
| `module.ecs.aws_ssm_parameter.be_config["AI_SIMULATION_MAX_PROCESSING_AGE_SECONDS"]` | `module.be.aws_ssm_parameter.be_config["AI_SIMULATION_MAX_PROCESSING_AGE_SECONDS"]` | `/star23/prod/be/AI_SIMULATION_MAX_PROCESSING_AGE_SECONDS` |
| `module.ecs.aws_ssm_parameter.be_config["AI_SIMULATION_PATH"]` | `module.be.aws_ssm_parameter.be_config["AI_SIMULATION_PATH"]` | `/star23/prod/be/AI_SIMULATION_PATH` |
| `module.ecs.aws_ssm_parameter.be_config["AI_SIMULATION_READ_TIMEOUT_MS"]` | `module.be.aws_ssm_parameter.be_config["AI_SIMULATION_READ_TIMEOUT_MS"]` | `/star23/prod/be/AI_SIMULATION_READ_TIMEOUT_MS` |
| `module.ecs.aws_ssm_parameter.be_config["APP_FILE_ALLOWED_MIME_TYPES"]` | `module.be.aws_ssm_parameter.be_config["APP_FILE_ALLOWED_MIME_TYPES"]` | `/star23/prod/be/APP_FILE_ALLOWED_MIME_TYPES` |
| `module.ecs.aws_ssm_parameter.be_config["APP_FILE_CLEANUP_BATCH_SIZE"]` | `module.be.aws_ssm_parameter.be_config["APP_FILE_CLEANUP_BATCH_SIZE"]` | `/star23/prod/be/APP_FILE_CLEANUP_BATCH_SIZE` |
| `module.ecs.aws_ssm_parameter.be_config["APP_FILE_CLEANUP_DELAY_MS"]` | `module.be.aws_ssm_parameter.be_config["APP_FILE_CLEANUP_DELAY_MS"]` | `/star23/prod/be/APP_FILE_CLEANUP_DELAY_MS` |
| `module.ecs.aws_ssm_parameter.be_config["APP_FILE_MAX_SIZE_BYTES"]` | `module.be.aws_ssm_parameter.be_config["APP_FILE_MAX_SIZE_BYTES"]` | `/star23/prod/be/APP_FILE_MAX_SIZE_BYTES` |
| `module.ecs.aws_ssm_parameter.be_config["APP_FILE_UPLOAD_INTENT_RETENTION"]` | `module.be.aws_ssm_parameter.be_config["APP_FILE_UPLOAD_INTENT_RETENTION"]` | `/star23/prod/be/APP_FILE_UPLOAD_INTENT_RETENTION` |
| `module.ecs.aws_ssm_parameter.be_config["APP_FILE_UPLOAD_INTENT_TTL"]` | `module.be.aws_ssm_parameter.be_config["APP_FILE_UPLOAD_INTENT_TTL"]` | `/star23/prod/be/APP_FILE_UPLOAD_INTENT_TTL` |
| `module.ecs.aws_ssm_parameter.be_config["AUTHORIZATION_URI"]` | `module.be.aws_ssm_parameter.be_config["AUTHORIZATION_URI"]` | `/star23/prod/be/AUTHORIZATION_URI` |
| `module.ecs.aws_ssm_parameter.be_config["AUTH_ALLOWED_ORIGINS"]` | `module.be.aws_ssm_parameter.be_config["AUTH_ALLOWED_ORIGINS"]` | `/star23/prod/be/AUTH_ALLOWED_ORIGINS` |
| `module.ecs.aws_ssm_parameter.be_config["AUTH_COOKIE_SAME_SITE"]` | `module.be.aws_ssm_parameter.be_config["AUTH_COOKIE_SAME_SITE"]` | `/star23/prod/be/AUTH_COOKIE_SAME_SITE` |
| `module.ecs.aws_ssm_parameter.be_config["AUTH_COOKIE_SECURE"]` | `module.be.aws_ssm_parameter.be_config["AUTH_COOKIE_SECURE"]` | `/star23/prod/be/AUTH_COOKIE_SECURE` |
| `module.ecs.aws_ssm_parameter.be_config["AUTH_ONBOARDING_REDIRECT_URI"]` | `module.be.aws_ssm_parameter.be_config["AUTH_ONBOARDING_REDIRECT_URI"]` | `/star23/prod/be/AUTH_ONBOARDING_REDIRECT_URI` |
| `module.ecs.aws_ssm_parameter.be_config["AUTH_REGISTRATION_REDIRECT_URI"]` | `module.be.aws_ssm_parameter.be_config["AUTH_REGISTRATION_REDIRECT_URI"]` | `/star23/prod/be/AUTH_REGISTRATION_REDIRECT_URI` |
| `module.ecs.aws_ssm_parameter.be_config["AUTH_SERVICE_REDIRECT_URI"]` | `module.be.aws_ssm_parameter.be_config["AUTH_SERVICE_REDIRECT_URI"]` | `/star23/prod/be/AUTH_SERVICE_REDIRECT_URI` |
| `module.ecs.aws_ssm_parameter.be_config["AWS_S3_BUCKET"]` | `module.be.aws_ssm_parameter.be_config["AWS_S3_BUCKET"]` | `/star23/prod/be/AWS_S3_BUCKET` |
| `module.ecs.aws_ssm_parameter.be_config["AWS_S3_DOWNLOAD_URL_EXPIRATION"]` | `module.be.aws_ssm_parameter.be_config["AWS_S3_DOWNLOAD_URL_EXPIRATION"]` | `/star23/prod/be/AWS_S3_DOWNLOAD_URL_EXPIRATION` |
| `module.ecs.aws_ssm_parameter.be_config["AWS_S3_REGION"]` | `module.be.aws_ssm_parameter.be_config["AWS_S3_REGION"]` | `/star23/prod/be/AWS_S3_REGION` |
| `module.ecs.aws_ssm_parameter.be_config["AWS_S3_UPLOAD_URL_EXPIRATION"]` | `module.be.aws_ssm_parameter.be_config["AWS_S3_UPLOAD_URL_EXPIRATION"]` | `/star23/prod/be/AWS_S3_UPLOAD_URL_EXPIRATION` |
| `module.ecs.aws_ssm_parameter.be_config["CLIENT_ID"]` | `module.be.aws_ssm_parameter.be_config["CLIENT_ID"]` | `/star23/prod/be/CLIENT_ID` |
| `module.ecs.aws_ssm_parameter.be_config["DB_URL"]` | `module.be.aws_ssm_parameter.be_config["DB_URL"]` | `/star23/prod/be/DB_URL` |
| `module.ecs.aws_ssm_parameter.be_config["DB_USERNAME"]` | `module.be.aws_ssm_parameter.be_config["DB_USERNAME"]` | `/star23/prod/be/DB_USERNAME` |
| `module.ecs.aws_ssm_parameter.be_config["JWT_PENDING_EXPIRATION_MINUTES"]` | `module.be.aws_ssm_parameter.be_config["JWT_PENDING_EXPIRATION_MINUTES"]` | `/star23/prod/be/JWT_PENDING_EXPIRATION_MINUTES` |
| `module.ecs.aws_ssm_parameter.be_config["JWT_REFRESH_EXPIRATION_DAYS"]` | `module.be.aws_ssm_parameter.be_config["JWT_REFRESH_EXPIRATION_DAYS"]` | `/star23/prod/be/JWT_REFRESH_EXPIRATION_DAYS` |
| `module.ecs.aws_ssm_parameter.be_config["JWT_SERVICE_EXPIRATION_MINUTES"]` | `module.be.aws_ssm_parameter.be_config["JWT_SERVICE_EXPIRATION_MINUTES"]` | `/star23/prod/be/JWT_SERVICE_EXPIRATION_MINUTES` |
| `module.ecs.aws_ssm_parameter.be_config["LOGGING_LEVEL_HIBERNATE_BIND"]` | `module.be.aws_ssm_parameter.be_config["LOGGING_LEVEL_HIBERNATE_BIND"]` | `/star23/prod/be/LOGGING_LEVEL_HIBERNATE_BIND` |
| `module.ecs.aws_ssm_parameter.be_config["LOGGING_LEVEL_HIBERNATE_SQL"]` | `module.be.aws_ssm_parameter.be_config["LOGGING_LEVEL_HIBERNATE_SQL"]` | `/star23/prod/be/LOGGING_LEVEL_HIBERNATE_SQL` |
| `module.ecs.aws_ssm_parameter.be_config["REDIRECT_URI"]` | `module.be.aws_ssm_parameter.be_config["REDIRECT_URI"]` | `/star23/prod/be/REDIRECT_URI` |
| `module.ecs.aws_ssm_parameter.be_config["SERVER_TOMCAT_MBEANREGISTRY_ENABLED"]` | `module.be.aws_ssm_parameter.be_config["SERVER_TOMCAT_MBEANREGISTRY_ENABLED"]` | `/star23/prod/be/SERVER_TOMCAT_MBEANREGISTRY_ENABLED` |
| `module.ecs.aws_ssm_parameter.be_config["SPRING_PROFILES_ACTIVE"]` | `module.be.aws_ssm_parameter.be_config["SPRING_PROFILES_ACTIVE"]` | `/star23/prod/be/SPRING_PROFILES_ACTIVE` |
| `module.ecs.aws_ssm_parameter.be_config["TOKEN_URI"]` | `module.be.aws_ssm_parameter.be_config["TOKEN_URI"]` | `/star23/prod/be/TOKEN_URI` |
| `module.ecs.aws_ssm_parameter.be_config["USER_INFO_URI"]` | `module.be.aws_ssm_parameter.be_config["USER_INFO_URI"]` | `/star23/prod/be/USER_INFO_URI` |
| `module.network.aws_security_group.app` | `module.be.aws_security_group.app` | `sg-0503c9272aec02938` |
| `module.network.aws_security_group.ecs_service["ai"]` | `module.ai.module.runtime.aws_security_group.service` | `sg-0b0c8b8bf5a2ad320` |
| `module.network.aws_security_group.ecs_service["ws"]` | `module.ws.module.runtime.aws_security_group.service` | `sg-0485ff24c6d6eec2e` |
| `module.network.aws_vpc_security_group_egress_rule.alb_to_app` | `aws_vpc_security_group_egress_rule.alb_to_app` | `sgr-02fc698b70927d7c1` |
| `module.network.aws_vpc_security_group_egress_rule.alb_to_ws` | `aws_vpc_security_group_egress_rule.alb_to_ws` | `sgr-0b5e6d320c19b544a` |
| `module.network.aws_vpc_security_group_egress_rule.app_outbound_rule` | `module.be.aws_vpc_security_group_egress_rule.app_outbound_rule` | `sgr-05f1f0f7b7865b239` |
| `module.network.aws_vpc_security_group_egress_rule.ecs_service_outbound["ai"]` | `module.ai.module.runtime.aws_vpc_security_group_egress_rule.outbound` | `sgr-034a8e20bc40df1e4` |
| `module.network.aws_vpc_security_group_egress_rule.ecs_service_outbound["ws"]` | `module.ws.module.runtime.aws_vpc_security_group_egress_rule.outbound` | `sgr-0b2bfe7a7cb1470a5` |
| `module.network.aws_vpc_security_group_ingress_rule.additional_ecs_database["ai-postgres"]` | `aws_vpc_security_group_ingress_rule.additional_ecs_database["ai-postgres"]` | `sgr-0c2393df6938f93fb` |
| `module.network.aws_vpc_security_group_ingress_rule.additional_ecs_database["ws-mysql"]` | `aws_vpc_security_group_ingress_rule.additional_ecs_database["ws-mysql"]` | `sgr-0a80d1f7411594df8` |
| `module.network.aws_vpc_security_group_ingress_rule.ai_from_be` | `aws_vpc_security_group_ingress_rule.ai_from_be` | `sgr-0528c999524434f7c` |
| `module.network.aws_vpc_security_group_ingress_rule.app_from_alb` | `aws_vpc_security_group_ingress_rule.app_from_alb` | `sgr-0bb3baa52933f1ec9` |
| `module.network.aws_vpc_security_group_ingress_rule.mysql_from_app` | `aws_vpc_security_group_ingress_rule.mysql_from_app` | `sgr-0897b025695403eae` |
| `module.network.aws_vpc_security_group_ingress_rule.postgres_from_app` | `aws_vpc_security_group_ingress_rule.postgres_from_app` | `sgr-0ed715c2b39a0e5c7` |
| `module.network.aws_vpc_security_group_ingress_rule.v1_database_from_ecs["ai-postgres"]` | `aws_vpc_security_group_ingress_rule.v1_database_from_ecs["ai-postgres"]` | `sgr-0d6025812fca4a2dc` |
| `module.network.aws_vpc_security_group_ingress_rule.v1_database_from_ecs["be-mysql"]` | `aws_vpc_security_group_ingress_rule.v1_database_from_ecs["be-mysql"]` | `sgr-00196f9539d6df5c0` |
| `module.network.aws_vpc_security_group_ingress_rule.v1_database_from_ecs["ws-mysql"]` | `aws_vpc_security_group_ingress_rule.v1_database_from_ecs["ws-mysql"]` | `sgr-0d67698cac3485b4d` |
| `module.network.aws_vpc_security_group_ingress_rule.ws_from_alb` | `aws_vpc_security_group_ingress_rule.ws_from_alb` | `sgr-06efbf0a90350fbe1` |

## 동일 주소를 유지하는 prod 소유권 (43건)

아래 객체는 주소와 ID 모두 유지한다. 94개 이동 + 43개 동일 주소의 기존 객체 137개가
모두 no-op이며, 과거 기록 해제 2개와 기존 자원 import 7개만 별도로 제안한다.

| 유지 주소 / 소유자 | 유지 ID |
| --- | --- |
| `module.alb.aws_alb.main` | `arn:aws:elasticloadbalancing:ap-northeast-2:975779326240:loadbalancer/app/star23-alb/1ca5051586e3c967` |
| `module.alb.aws_lb_listener.http` | `arn:aws:elasticloadbalancing:ap-northeast-2:975779326240:listener/app/star23-alb/1ca5051586e3c967/6e1f17ada487ab23` |
| `module.alb.aws_lb_listener.https` | `arn:aws:elasticloadbalancing:ap-northeast-2:975779326240:listener/app/star23-alb/1ca5051586e3c967/7486e2341aeaa359` |
| `module.alb.aws_lb_target_group.api` | `arn:aws:elasticloadbalancing:ap-northeast-2:975779326240:targetgroup/star23-api-tg/79eff3c262528548` |
| `module.alb.aws_lb_target_group.ws` | `arn:aws:elasticloadbalancing:ap-northeast-2:975779326240:targetgroup/star23-ws-tg/6cdd5b0633211dc3` |
| `module.database.aws_db_instance.mysql` | `db-X2EDA56PDOYXTSMH2RGQZ6J7YU` |
| `module.database.aws_db_instance.postgres` | `db-AHSDB5A3WKWXTJWQZJCJBZIMN4` |
| `module.database.aws_db_subnet_group.mysql` | `star23-v2-prod-data` |
| `module.database.aws_db_subnet_group.postgres` | `star23-v2-prod-postgres-data` |
| `module.network.aws_eip.nat["2a"]` | `eipalloc-0e41c9d00af323112` |
| `module.network.aws_internet_gateway.main` | `igw-02eaf0022aad0070a` |
| `module.network.aws_nat_gateway.main["2a"]` | `nat-0df854ae52c66ac3c` |
| `module.network.aws_route.app_nat["2a"]` | `r-rtb-0483eafe0a88f9d6f1080289494` |
| `module.network.aws_route.app_nat["2c"]` | `r-rtb-0eff246d8f32b92171080289494` |
| `module.network.aws_route.application_to_v1_database["2a"]` | `r-rtb-0483eafe0a88f9d6f179966490` |
| `module.network.aws_route.application_to_v1_database["2c"]` | `r-rtb-0eff246d8f32b9217179966490` |
| `module.network.aws_route.public_internet` | `r-rtb-0da387175796d3fe01080289494` |
| `module.network.aws_route.v1_database_to_application["rtb-07a5c07f85fda1ee1-2a"]` | `r-rtb-07a5c07f85fda1ee12101771648` |
| `module.network.aws_route.v1_database_to_application["rtb-07a5c07f85fda1ee1-2c"]` | `r-rtb-07a5c07f85fda1ee13055201829` |
| `module.network.aws_route_table.application["2a"]` | `rtb-0483eafe0a88f9d6f` |
| `module.network.aws_route_table.application["2c"]` | `rtb-0eff246d8f32b9217` |
| `module.network.aws_route_table.data["2a"]` | `rtb-061fe91000cf4bac3` |
| `module.network.aws_route_table.data["2c"]` | `rtb-0ea2022951d7d40dc` |
| `module.network.aws_route_table.public` | `rtb-0da387175796d3fe0` |
| `module.network.aws_route_table_association.application["2a"]` | `rtbassoc-0411dd8c467194b72` |
| `module.network.aws_route_table_association.application["2c"]` | `rtbassoc-0474a20b0ebf385df` |
| `module.network.aws_route_table_association.data["2a"]` | `rtbassoc-0b6fa7161c2145f52` |
| `module.network.aws_route_table_association.data["2c"]` | `rtbassoc-031ed42a96ab91c32` |
| `module.network.aws_route_table_association.public["2a"]` | `rtbassoc-063fe6129ccc0dd87` |
| `module.network.aws_route_table_association.public["2c"]` | `rtbassoc-0fe29c1479e9212e1` |
| `module.network.aws_security_group.alb` | `sg-024bc8ce4703437e4` |
| `module.network.aws_security_group.mysql` | `sg-06ac6e738fe2627b8` |
| `module.network.aws_security_group.postgres` | `sg-079aa290fd348d89d` |
| `module.network.aws_subnet.application["2a"]` | `subnet-0df254967b351e8b4` |
| `module.network.aws_subnet.application["2c"]` | `subnet-026d0c5d6c7d078ab` |
| `module.network.aws_subnet.data["2a"]` | `subnet-0216b16db5b704108` |
| `module.network.aws_subnet.data["2c"]` | `subnet-00d8529fb49a24255` |
| `module.network.aws_subnet.public["2a"]` | `subnet-0ed1f69eb87aa7bb0` |
| `module.network.aws_subnet.public["2c"]` | `subnet-0c6f943221f9a3261` |
| `module.network.aws_vpc.main` | `vpc-021d4bdf5e5e79b3e` |
| `module.network.aws_vpc_peering_connection.v1_database["v1"]` | `pcx-09f9b6ffb8454c7b9` |
| `module.network.aws_vpc_security_group_ingress_rule.alb_http` | `sgr-00c25d9943f76232f` |
| `module.network.aws_vpc_security_group_ingress_rule.alb_https` | `sgr-06e08b147695b3503` |
