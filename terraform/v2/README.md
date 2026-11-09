# 운영 인프라

독립 backend `prod/terraform.tfstate`를 유지한다. CloudFront·공통 S3·ECR은 [common](../common/README.md)이 소유하며, 이 루트는 `common.tf`에서 필요한 출력만 읽는다. 소유권·새 환경의 단계별 순서는 [루트 README](../../README.md)를 따른다. 2026-11-09 소유권과 주소 이관을 원격 state에 반영했다. 이어 운영 모니터링을 V2로 이전하고 V1 피어링·경로·교차 SG 규칙을 제거했다. 앱 task revision과 실행 수는 유지했다.

```sh
terraform -chdir=terraform/v2 init -input=false -lockfile=readonly
terraform -chdir=terraform/v2 validate
```

입력은 권한 제한된 로컬 파일을 명시적 `-var-file`로 전달한다. 현재 재실행용 파일은 저장소에서 제외되는 `.terraform-private/v2.tfvars.json`(0600)이다. 저장소 루트에서 `terraform -chdir=terraform/v2 plan -input=false -lock-timeout=60s -var-file=../../.terraform-private/v2.tfvars.json`으로 검토한다. 앱 설정값이나 비밀값을 담은 이전 입력 파일은 재사용하지 않는다.

| 입력 | 계약 |
| --- | --- |
| `acm_certificate_arn` | 기존 외부 인증서 ARN |
| `monitoring_security_group_id` | 독립 cloudwatch 루트의 `monitoring.security_group_id` 출력. BE·WS 메트릭 접근용이며 필수 입력이다. 새 환경에서 모니터링 생성 전에는 명시적으로 null |
| `services_enabled` | 기본 true. 기존 서비스는 true 유지. **새 환경 1단계만 false** |
| `task_definition_arns` | `{be, ai, ws}` 외부 등록 task ARN(리비전 포함). 생성하는 서비스마다 필수. 이미지/CPU/환경/실행 수 입력 없음 |
| `ws_infrastructure` | `enabled`, `use_backend_config` 기본 true. 기존 `ws_deployment`의 두 bool을 그대로 이전. WS IAM·로그·서비스·공유 접근/Service Connect 범위. ALB route/target group은 기존처럼 항상 유지 |
| `be_access` | `parameter_arns` map에 기존 `be_runtime.environment`의 각 SSM ARN을 **값 없이** 옮김. `secrets`, `kms_key_arns`는 기존 ARN 참조 유지 |
| `ai_access` | 이전 `ai_runtime`에서 ARN-only `secrets`, `kms_key_arns`, `additional_execution_secret_arns`만 이전 |
| `ws_access` | 이전 `ws_runtime`에서 ARN-only `secrets`, `kms_key_arns`만 이전 |

ARN map의 key는 권한 참조용 식별자이며 환경 내용을 생성하지 않는다. Secret 참조에는 JSON key/version selector를 허용하되 IAM Resource에는 원본 secret ARN만 사용한다. Secret 컨테이너 ARN도 허용 정책에 유지한다. Terraform은 Secret/SSM 값을 조회하거나 새 version을 발행하지 않는다. `config_references`와 `deployment_infrastructure`는 ARN/역할/로그/ECR 등 인프라 정보만 제공한다.

삭제된 `be_secret_values`, `ai_secret_values`, `be_secret_version`, `*_runtime.environment`, 이미지·아키텍처·원하는 태스크 수는 외부 배포 소유다. 이전 `*_deployment` 객체는 제거됐다. 별도 root인 `cloudwatch/` 입력과 섞지 않는다. NAT 하나를 두 AZ가 공유하는 기존 네트워크 구조와 ALB/SG/DB 설정은 유지한다.

## SG 소유권과 고정 DB 접근

SG와 접근 규칙은 각 소유 리소스의 `security.tf`에서 함께 관리한다. 서비스 간 연결에는 상대 SG ID와 포트만 전달한다. DB 종류를 고르는 선택 변수는 사용하지 않는다.

| 파일 | 관리하는 접근 규칙 |
| --- | --- |
| `alb/security.tf` | HTTP·HTTPS 수신, BE·WS로 송신 |
| `ecs/service/be/security.tf` | ALB 및 V2 모니터링에서 BE로 수신, BE 송신 |
| `ecs/service/ws/security.tf` | ALB 및 V2 모니터링에서 WS로 수신, WS 송신 |
| `ecs/service/ai/security.tf` | BE·WS에서 AI로 수신, AI 송신 |
| `database/security.tf` | MySQL은 BE·WS, PostgreSQL은 BE·AI 접근 |

V1 네트워크 입력과 DB 접근 규칙은 제거했다. V2 모니터링은 BE·WS TCP 8080을 SG 참조로 수집한다. WS 서비스를 비활성화해도 기존 SG와 고정 DB 접근 규칙은 유지한다.

기존 루트 규칙 13개와 BE·AI 서비스의 주소 이동은 원격 state에 반영했다. 규칙·서비스 ID를 유지한 것을 확인한 뒤 일회성 이관 선언을 제거했다.

SG ID 출력은 규칙 완료와 독립적이며, 규칙 ID 출력은 ECS 서비스 생성만 기다리게 한다.

| 클라이언트 | RDS MySQL 3306 | RDS PostgreSQL 5432 |
| --- | --- | --- |
| BE | 허용 | 허용 |
| WS | 허용 | 없음 |
| AI | 없음 | 허용 |

V1 피어링 입력은 기존 로컬 입력 파일에서도 제거한다. ACM·외부 task ARN·IAM secret-access 및 bootstrap 입력 계약은 유지한다.

2026-11-09 계정/리전을 확인한 뒤 원격 prod state의 관리 규칙 18개와 EC2의 ID·방향·SG 쌍·프로토콜·포트·설명·태그를 읽기 전용으로 대조했다. `-1` 프로토콜의 AWS 포트 `-1`은 provider state의 `null`과 동일한 전체 프로토콜 의미다. 확인된 접근만 고정 리소스로 옮기고 기존 ID를 유지했다. state·plan·비밀값은 저장소에 넣지 않는다.

`terraform test`의 mock plan은 외부 common 출력, fresh/WS 비활성/고정 V2 DB 접근 경로를 검증한다. 실제 이관에서는 백업 state와 이관 후 state의 모든 유지 대상 ID를 대조했다.

이관 시 전체 plan에서 기존 설정 차이 6건을 확인했지만 적용하지 않았다. WS target group의 health 경로, RDS 2개의 backup retention(AWS 3일/코드 7일), public subnet 2개의 Kubernetes 태그, WS execution policy의 중복 statement 정리다. 소유권 이관과 별도로 검토하며, 이관 검증이 전체 인프라 plan의 무변경을 의미하지 않는다.
