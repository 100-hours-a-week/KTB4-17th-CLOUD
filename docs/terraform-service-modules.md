# #5 환경별 리소스 모듈과 서비스 소유권 — PR #14

최신 검증과 dev 외부 자원별 근거는 [환경 분리 검증](terraform-environment-separation.md)을 따른다.
V1 dev와 V2 prod의 `main.tf`는 각 환경 바로 아래 실제 리소스 모듈을 조합한다.
`modules/` 또는 `environments/` wrapper와 옛 실행 가능한 `terraform/*.tf`는 없다.

prod `network/{vpc,subnet,routetable}`은 VPC/IGW, 계층 subnet, route table/association/default route를
각각 소유한다. NAT와 V1 peering/양방향 route는 network 부모에 유지한다.
ALB SG와 HTTP/HTTPS base rule은 `alb/security.tf`, MySQL·PostgreSQL SG는 `database/security.tf`,
ECS SG/egress는 `ecs/service/{be,ws,ai}/security.tf`, 교차 규칙은 prod `connections.tf`에 둔다.
dev는 `ec2`가 app/messaging, `database`가 data EC2를 소유하며 network와 legacy SG는 외부 참조다.

| root | bucket `star23-tfstate-975779326240`의 key | 상태 |
| --- | --- | --- |
| terraform/dev | dev/terraform.tfstate | EC2 3대 편입 완료, serial1 |
| terraform/prod | prod/terraform.tfstate | state 주소 정리 완료, 기존 lineage 유지, serial30 |
| terraform/prod/cloudwatch-loki | prod/cloudwatch-loki/terraform.tfstate | serial4 유지, 기존 module.cloudwatch_loki 주소 보존 |

공유 CloudFront/S3/ECR는 prod 단일 소유다. dev alias를 근거로 중복 편입하지 않는다.
기준 main `d6da1e92d26fdf0c4105586c277c7f1395fc29c9`, published 8개와 checkpoint `62cd3c8`을 보존한다.

## 서비스 설계

- `ecs/cluster`: 공유 cluster/namespace.
- `ecs/service/be`: BE task/service, SG/egress, 기존 IAM, logs, SSM 및 공유 Secret/version 소유.
- `ecs/service/ws`: WS task/service, 전용 SG/egress·IAM·logs·S3 정책과 config/secret 참조를 서비스 폴더에서 직접 소유.
- `ecs/service/ai`: AI task/service, 전용 SG/egress·IAM·logs와 config/secret·CI 리비전 추가 secret 권한을 직접 소유.
- `connections.tf`: 서비스/ALB/DB 간 SG edge를 단독 소유한다. 서비스 모듈 간 역참조와 network→service 순환을 만들지 않는다.

root가 cluster ID/namespace ARN, 선택한 subnet IDs, ALB target group ARN,
ECR/S3 ARN과 config 참조를 명시적으로 전달한다. shared network가 subnet을 생성하고
서비스가 배치 입력을 선택한다. BE의 기존 AWS 역할 이름은 바꾸지 않는다.
세 서비스 모두 CI/CD의 실제 task revision 소유권(`ignore_changes`)을 유지한다.
BE의 `config_references` 출력은 공유 Secret/version 완료를 보장한다. AI task만
이 출력을 의존하며, BE service만 AI의 `service_name` 출력을 의존한다.
따라서 **Secret → version → AI task → healthy AI service → BE service** 순서다.
기존 `wait_for_steady_state = true`와 AI 컨테이너 healthCheck를 유지한다.
BE 모듈 전체의 AI 의존성, 순환, 인위적인 readiness 리소스는 없다.

WS SG/egress와 연결 규칙은 기존 모델처럼 WS enable 여부와 별개로 소유하며,
WS task/service/IAM/log만 enable 조건을 따른다.


## 실제 state 전환과 최종 정상 소스 검증

2026-11-04 실행 승인 후 최신 소유권과 실제 S3 backend plan을 재검증하고 versioned 백업을 확보했다.
잠금 아래 prod 121 move/7 import/2 forget과 dev 3 import를 순서대로 적용했다.
prod 기존 137개 ID를 보존한 144개 managed 객체, dev 3개 정확한 ID를 확인했다.
Loki/staging 계열 state와 EIP allocation/association은 그대로다.

임시 선언 제거 후 실제 저장소 dev/prod/Loki 세 루트의 full-refresh plan은 detailed exit 0,
create/update/delete/replace/import/forget/move 모두 0이다. prod output 8개도 no-op이다.
ALB chat rule의 중복 top-level target_group_arn만 제거해 provider 읽기 표현에 맞췄으며,
실제 forward 대상/weight/stickiness/priority/경로를 바꾸거나 AWS update plan을 적용하지 않았다.
현재 소스 SHA256은 `21c367d55eb4740734cf27d2b6475fedc133306954b4c354d63329dd4924cc94`,
현재 실제 graph SHA256은 `2d4a4d7bf3afc29f00aa132cf2aa72d5e9b7fe5528cc78dd52770e496881ec13` (698 edges)다.
수정 후 전체 테스트 27개가 통과했다. 상세 실행·백업·최종 시각은 [환경 분리 검증](terraform-environment-separation.md)을 따른다.

## 전환 전 읽기 전용 preview 기록

아래는 2026-11-04 account975779326240/IAMnoel/regionap-northeast-2의 실행 전 기록이다.
prod는 private 사본의 임시 moved/import/removed, dev는 backend 없는 private 빈 state의 임시 import만 사용했다.
원격 state와 AWS 객체에 쓰지 않았고, full refresh에 target/refresh 생략 또는 dummy Secret을 사용하지 않았다.

| plan | create | update | delete | replace | import | forget | move |
| --- | --- | --- | --- | --- | --- | --- | --- |
| prod state-only 제안 | 0 | 0 | 0 | 0 | 7 | 2 | 121 |
| 독립 Loki | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| dev import-only 제안 | 0 | 0 | 0 | 0 | 3 | 0 | 0 |

세 plan complete=true/errored=false/deferred 없음. prod 기존 137개 ID와 모든 기존 객체의 no-op,
두 RDS, ALB idle120/chat route, 공유 CDN 구성, live CI task revision/desired count 3개를 유지한다.
당시 preview 자체는 실제 편입 결과가 아니었다. 당시 다섯 backend의 bytes/lineage/serial은
전후 동일했고 dev key가 없었다. 현재 편입 완료와 정상 소스 no-op은 위 절에서 별도로 검증했다.

`check_readonly_plan.py`는 모든 AWS write/replacement, incomplete/errored/deferred, action invocation,
미승인·누락·추가 import/move/forget, move 전후 ID 불일치/unknown을 거절한다.
`verify_environment_previews.py`는 전환 전 소스 해시와 private 사본, 정확한 manifest, 기존 ID 전체,
5개 remote snapshot 동일성, dev 중복 소유권 부재와 live CI revision을 검사했던 역사적 증거용이다.
현재 일상 plan은 manifest 없는 `check_readonly_plan.py`로 검증한다.
27개 unittest는 실제 Terraform graph, 소스 변이, 조건부 V1/WS/AI DB 입력 96개 결과,
서비스별 readiness와 module-wide gate/cycle 부재를 검사한다. 새 중첩 network 경로도 검증한다.
provider cache 없는 clean 사본의 환경 테스트 3개도 통과했다.

전환 전 소스 집합 SHA256: `c8a22fca4e4de40d44f91d362f0569ba1e37704ac7cbd90b9431cbeec9a754f1`.
전환 전 prod graph SHA256: `04e7a8039ae2e34b8f1965e2960cc56a989e038807572b02f340d8ee439a9644`, 1024 edges.

재검증 명령과 제외 dev 자원별 근거는 [환경 분리 검증](terraform-environment-separation.md)에 있다.
raw state/plan/tfvars/Secret/ZIP/.terraform은 저장소 밖 private 파일로만 보관한다.
tracked import/moved/removed 블록과 영구 migration 디렉터리는 없다.

## 실행한 정확한 import / forget 기록

| 동작 | 주소 | 정확한 기존 ID |
| --- | --- | --- |
| import 완료 | `module.cdn.aws_cloudfront_distribution.fe` | `E3LYSMQO2T1UT` |
| import 완료 | `module.storage.aws_ecr_repository.be` | `star23/be` |
| import 완료 | `module.storage.aws_ecr_repository.ai` | `star23/ai` |
| import 완료 | `module.storage.aws_s3_bucket.fe` | `star23-s3-deploy-bucket-975779326240-ap-northeast-2-an` |
| import 완료 | `module.storage.aws_s3_bucket.image` | `star23-images` |
| import 완료 | `module.alb.aws_lb_listener_rule.chat_routes` | `arn:aws:elasticloadbalancing:ap-northeast-2:975779326240:listener-rule/app/star23-alb/1ca5051586e3c967/7486e2341aeaa359/a1bcba60b2a96fb8` |
| import 완료 | `aws_vpc_security_group_ingress_rule.ai_from_ws` | `sgr-0030fb498843e37b8` |
| forget 완료 | `module.alb.aws_lb_listener_rule.ws` | `arn:aws:elasticloadbalancing:ap-northeast-2:975779326240:listener-rule/app/star23-alb/1ca5051586e3c967/7486e2341aeaa359/f8cd5cf50f103400` |
| forget 완료 | `module.alb.aws_lb_listener_rule.ws_ai_practice` | `arn:aws:elasticloadbalancing:ap-northeast-2:975779326240:listener-rule/app/star23-alb/1ca5051586e3c967/7486e2341aeaa359/0abaf0678dd25457` |

두 forget은 이미 사라진 ALB 규칙의 state 기록만 해제했으며 AWS 삭제가 아니다.

## 정확한 주소 이동 / 기존 ID 유지 표 (121건)

| 기존 주소 | 최종 주소 | 유지하는 기존 ID |
| --- | --- | --- |
| `module.ecs.aws_cloudwatch_log_group.service["ai"]` | `module.ai.aws_cloudwatch_log_group.service[0]` | `/ecs/star23/prod/ai` |
| `module.ecs.aws_cloudwatch_log_group.service["be"]` | `module.be.aws_cloudwatch_log_group.service` | `/ecs/star23/prod/be` |
| `module.ecs.aws_cloudwatch_log_group.service["ws"]` | `module.ws.aws_cloudwatch_log_group.service[0]` | `/ecs/star23/prod/ws` |
| `module.ecs.aws_ecs_cluster.main` | `module.cluster.aws_ecs_cluster.main` | `arn:aws:ecs:ap-northeast-2:975779326240:cluster/star23-ecs-cluster` |
| `module.ecs.aws_ecs_service.ai` | `module.ai.aws_ecs_service.ai` | `arn:aws:ecs:ap-northeast-2:975779326240:service/star23-ecs-cluster/star23-ai-service` |
| `module.ecs.aws_ecs_service.be` | `module.be.aws_ecs_service.be` | `arn:aws:ecs:ap-northeast-2:975779326240:service/star23-ecs-cluster/star23-be-service` |
| `module.ecs.aws_ecs_service.ws[0]` | `module.ws.aws_ecs_service.ws[0]` | `arn:aws:ecs:ap-northeast-2:975779326240:service/star23-ecs-cluster/star23-ws-service` |
| `module.ecs.aws_ecs_task_definition.ai` | `module.ai.aws_ecs_task_definition.ai` | `star23-ai` |
| `module.ecs.aws_ecs_task_definition.be` | `module.be.aws_ecs_task_definition.be` | `star23-be` |
| `module.ecs.aws_ecs_task_definition.ws[0]` | `module.ws.aws_ecs_task_definition.ws[0]` | `star23-ws` |
| `module.ecs.aws_iam_role.ecs_execution` | `module.be.aws_iam_role.ecs_execution` | `star23-ecs-execution-role` |
| `module.ecs.aws_iam_role.ecs_task` | `module.be.aws_iam_role.ecs_task` | `star23-ecs-task-role` |
| `module.ecs.aws_iam_role.service_execution["ai"]` | `module.ai.aws_iam_role.service_execution["ai"]` | `star23-ai-ecs-execution-role` |
| `module.ecs.aws_iam_role.service_execution["ws"]` | `module.ws.aws_iam_role.service_execution["ws"]` | `star23-ws-ecs-execution-role` |
| `module.ecs.aws_iam_role.service_task["ai"]` | `module.ai.aws_iam_role.service_task["ai"]` | `star23-ai-ecs-task-role` |
| `module.ecs.aws_iam_role.service_task["ws"]` | `module.ws.aws_iam_role.service_task["ws"]` | `star23-ws-ecs-task-role` |
| `module.ecs.aws_iam_role_policy.be_s3` | `module.be.aws_iam_role_policy.be_s3` | `star23-ecs-task-role:star23-be-s3` |
| `module.ecs.aws_iam_role_policy.ecs_execution_secrets[0]` | `module.be.aws_iam_role_policy.ecs_execution_secrets[0]` | `star23-ecs-execution-role:star23-ecs-execution-secrets` |
| `module.ecs.aws_iam_role_policy.service_execution_secrets["ai"]` | `module.ai.aws_iam_role_policy.service_execution_secrets["ai"]` | `star23-ai-ecs-execution-role:star23-ai-ecs-execution-secrets` |
| `module.ecs.aws_iam_role_policy.service_execution_secrets["ws"]` | `module.ws.aws_iam_role_policy.service_execution_secrets["ws"]` | `star23-ws-ecs-execution-role:star23-ws-ecs-execution-secrets` |
| `module.ecs.aws_iam_role_policy.ws_s3[0]` | `module.ws.aws_iam_role_policy.ws_s3[0]` | `star23-ws-ecs-task-role:star23-ws-s3` |
| `module.ecs.aws_iam_role_policy_attachment.ecs_execution` | `module.be.aws_iam_role_policy_attachment.ecs_execution` | `star23-ecs-execution-role/arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy` |
| `module.ecs.aws_iam_role_policy_attachment.service_execution["ai"]` | `module.ai.aws_iam_role_policy_attachment.service_execution["ai"]` | `star23-ai-ecs-execution-role/arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy` |
| `module.ecs.aws_iam_role_policy_attachment.service_execution["ws"]` | `module.ws.aws_iam_role_policy_attachment.service_execution["ws"]` | `star23-ws-ecs-execution-role/arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy` |
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
| `module.network.aws_internet_gateway.main` | `module.network.module.vpc.aws_internet_gateway.main` | `igw-02eaf0022aad0070a` |
| `module.network.aws_route.app_nat["2a"]` | `module.network.module.routetable.aws_route.app_nat["2a"]` | `r-rtb-0483eafe0a88f9d6f1080289494` |
| `module.network.aws_route.app_nat["2c"]` | `module.network.module.routetable.aws_route.app_nat["2c"]` | `r-rtb-0eff246d8f32b92171080289494` |
| `module.network.aws_route.public_internet` | `module.network.module.routetable.aws_route.public_internet` | `r-rtb-0da387175796d3fe01080289494` |
| `module.network.aws_route_table.application["2a"]` | `module.network.module.routetable.aws_route_table.application["2a"]` | `rtb-0483eafe0a88f9d6f` |
| `module.network.aws_route_table.application["2c"]` | `module.network.module.routetable.aws_route_table.application["2c"]` | `rtb-0eff246d8f32b9217` |
| `module.network.aws_route_table.data["2a"]` | `module.network.module.routetable.aws_route_table.data["2a"]` | `rtb-061fe91000cf4bac3` |
| `module.network.aws_route_table.data["2c"]` | `module.network.module.routetable.aws_route_table.data["2c"]` | `rtb-0ea2022951d7d40dc` |
| `module.network.aws_route_table.public` | `module.network.module.routetable.aws_route_table.public` | `rtb-0da387175796d3fe0` |
| `module.network.aws_route_table_association.application["2a"]` | `module.network.module.routetable.aws_route_table_association.application["2a"]` | `rtbassoc-0411dd8c467194b72` |
| `module.network.aws_route_table_association.application["2c"]` | `module.network.module.routetable.aws_route_table_association.application["2c"]` | `rtbassoc-0474a20b0ebf385df` |
| `module.network.aws_route_table_association.data["2a"]` | `module.network.module.routetable.aws_route_table_association.data["2a"]` | `rtbassoc-0b6fa7161c2145f52` |
| `module.network.aws_route_table_association.data["2c"]` | `module.network.module.routetable.aws_route_table_association.data["2c"]` | `rtbassoc-031ed42a96ab91c32` |
| `module.network.aws_route_table_association.public["2a"]` | `module.network.module.routetable.aws_route_table_association.public["2a"]` | `rtbassoc-063fe6129ccc0dd87` |
| `module.network.aws_route_table_association.public["2c"]` | `module.network.module.routetable.aws_route_table_association.public["2c"]` | `rtbassoc-0fe29c1479e9212e1` |
| `module.network.aws_security_group.alb` | `module.alb.aws_security_group.alb` | `sg-024bc8ce4703437e4` |
| `module.network.aws_security_group.app` | `module.be.aws_security_group.app` | `sg-0503c9272aec02938` |
| `module.network.aws_security_group.ecs_service["ai"]` | `module.ai.aws_security_group.service` | `sg-0b0c8b8bf5a2ad320` |
| `module.network.aws_security_group.ecs_service["ws"]` | `module.ws.aws_security_group.service` | `sg-0485ff24c6d6eec2e` |
| `module.network.aws_security_group.mysql` | `module.database.aws_security_group.mysql` | `sg-06ac6e738fe2627b8` |
| `module.network.aws_security_group.postgres` | `module.database.aws_security_group.postgres` | `sg-079aa290fd348d89d` |
| `module.network.aws_subnet.application["2a"]` | `module.network.module.subnet.aws_subnet.application["2a"]` | `subnet-0df254967b351e8b4` |
| `module.network.aws_subnet.application["2c"]` | `module.network.module.subnet.aws_subnet.application["2c"]` | `subnet-026d0c5d6c7d078ab` |
| `module.network.aws_subnet.data["2a"]` | `module.network.module.subnet.aws_subnet.data["2a"]` | `subnet-0216b16db5b704108` |
| `module.network.aws_subnet.data["2c"]` | `module.network.module.subnet.aws_subnet.data["2c"]` | `subnet-00d8529fb49a24255` |
| `module.network.aws_subnet.public["2a"]` | `module.network.module.subnet.aws_subnet.public["2a"]` | `subnet-0ed1f69eb87aa7bb0` |
| `module.network.aws_subnet.public["2c"]` | `module.network.module.subnet.aws_subnet.public["2c"]` | `subnet-0c6f943221f9a3261` |
| `module.network.aws_vpc.main` | `module.network.module.vpc.aws_vpc.main` | `vpc-021d4bdf5e5e79b3e` |
| `module.network.aws_vpc_security_group_egress_rule.alb_to_app` | `aws_vpc_security_group_egress_rule.alb_to_app` | `sgr-02fc698b70927d7c1` |
| `module.network.aws_vpc_security_group_egress_rule.alb_to_ws` | `aws_vpc_security_group_egress_rule.alb_to_ws` | `sgr-0b5e6d320c19b544a` |
| `module.network.aws_vpc_security_group_egress_rule.app_outbound_rule` | `module.be.aws_vpc_security_group_egress_rule.app_outbound_rule` | `sgr-05f1f0f7b7865b239` |
| `module.network.aws_vpc_security_group_egress_rule.ecs_service_outbound["ai"]` | `module.ai.aws_vpc_security_group_egress_rule.outbound` | `sgr-034a8e20bc40df1e4` |
| `module.network.aws_vpc_security_group_egress_rule.ecs_service_outbound["ws"]` | `module.ws.aws_vpc_security_group_egress_rule.outbound` | `sgr-0b2bfe7a7cb1470a5` |
| `module.network.aws_vpc_security_group_ingress_rule.additional_ecs_database["ai-postgres"]` | `aws_vpc_security_group_ingress_rule.additional_ecs_database["ai-postgres"]` | `sgr-0c2393df6938f93fb` |
| `module.network.aws_vpc_security_group_ingress_rule.additional_ecs_database["ws-mysql"]` | `aws_vpc_security_group_ingress_rule.additional_ecs_database["ws-mysql"]` | `sgr-0a80d1f7411594df8` |
| `module.network.aws_vpc_security_group_ingress_rule.ai_from_be` | `aws_vpc_security_group_ingress_rule.ai_from_be` | `sgr-0528c999524434f7c` |
| `module.network.aws_vpc_security_group_ingress_rule.alb_http` | `module.alb.aws_vpc_security_group_ingress_rule.alb_http` | `sgr-00c25d9943f76232f` |
| `module.network.aws_vpc_security_group_ingress_rule.alb_https` | `module.alb.aws_vpc_security_group_ingress_rule.alb_https` | `sgr-06e08b147695b3503` |
| `module.network.aws_vpc_security_group_ingress_rule.app_from_alb` | `aws_vpc_security_group_ingress_rule.app_from_alb` | `sgr-0bb3baa52933f1ec9` |
| `module.network.aws_vpc_security_group_ingress_rule.mysql_from_app` | `aws_vpc_security_group_ingress_rule.mysql_from_app` | `sgr-0897b025695403eae` |
| `module.network.aws_vpc_security_group_ingress_rule.postgres_from_app` | `aws_vpc_security_group_ingress_rule.postgres_from_app` | `sgr-0ed715c2b39a0e5c7` |
| `module.network.aws_vpc_security_group_ingress_rule.v1_database_from_ecs["ai-postgres"]` | `aws_vpc_security_group_ingress_rule.v1_database_from_ecs["ai-postgres"]` | `sgr-0d6025812fca4a2dc` |
| `module.network.aws_vpc_security_group_ingress_rule.v1_database_from_ecs["be-mysql"]` | `aws_vpc_security_group_ingress_rule.v1_database_from_ecs["be-mysql"]` | `sgr-00196f9539d6df5c0` |
| `module.network.aws_vpc_security_group_ingress_rule.v1_database_from_ecs["ws-mysql"]` | `aws_vpc_security_group_ingress_rule.v1_database_from_ecs["ws-mysql"]` | `sgr-0d67698cac3485b4d` |
| `module.network.aws_vpc_security_group_ingress_rule.ws_from_alb` | `aws_vpc_security_group_ingress_rule.ws_from_alb` | `sgr-06efbf0a90350fbe1` |

## 동일 주소 유지 객체

121개 이동과 아래 16개 동일 주소의 기존 ID, 총 137개를 유지한다.

| 주소 | 기존 ID |
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
| `module.network.aws_nat_gateway.main["2a"]` | `nat-0df854ae52c66ac3c` |
| `module.network.aws_route.application_to_v1_database["2a"]` | `r-rtb-0483eafe0a88f9d6f179966490` |
| `module.network.aws_route.application_to_v1_database["2c"]` | `r-rtb-0eff246d8f32b9217179966490` |
| `module.network.aws_route.v1_database_to_application["rtb-07a5c07f85fda1ee1-2a"]` | `r-rtb-07a5c07f85fda1ee12101771648` |
| `module.network.aws_route.v1_database_to_application["rtb-07a5c07f85fda1ee1-2c"]` | `r-rtb-07a5c07f85fda1ee13055201829` |
| `module.network.aws_vpc_peering_connection.v1_database["v1"]` | `pcx-09f9b6ffb8454c7b9` |

## 현재 운영과 남은 소유권 작업

승인한 state 전환과 dev EC2 편입 및 세 실제 루트의 최종 full-refresh no-op 검증을 완료했다.
이전 전환 plan을 재적용하지 않는다. 최신 소스로 일반 plan을 만들고 모든 변경을 검토한다.
#5는 dev 공유 V1 네트워크/SG/EIP/IAM의 추가 소유권 편입을 추적하며, EIP 정리는 #12에서 진행한다.
현재 편입 범위 밖 자원의 근거와 일상 명령은 환경 분리 문서에 있다. AWS 리소스·DNS·IAM은 변경하지 않았다.
