# 운영 인프라

독립 backend `prod/terraform.tfstate`를 유지한다. 소유권·비파괴 이관·새 환경의 단계별 순서는 [루트 README](../../README.md)를 따른다. 이 PR은 운영 반영/배포를 실행하지 않는다.

```sh
terraform -chdir=terraform/prod init -input=false -lockfile=readonly
terraform -chdir=terraform/prod validate
```

입력은 저장소 밖 파일을 명시적 `-var-file`로 전달한다. 앱 설정값이나 비밀값을 담은 이전 입력 파일은 재사용하지 않는다.

| 입력 | 계약 |
| --- | --- |
| `acm_certificate_arn`, `v1_database_network` | 기존 외부 인증서·V1 DB 네트워크 참조 유지 |
| `services_enabled` | 기본 true. 기존 서비스는 true 유지. **새 환경 1단계만 false** |
| `task_definition_arns` | `{be, ai, ws}` 외부 등록 task ARN(리비전 포함). 생성하는 서비스마다 필수. 이미지/CPU/환경/실행 수 입력 없음 |
| `ws_infrastructure` | `enabled`, `use_backend_config` 기본 true. 기존 `ws_deployment`의 두 bool을 그대로 이전. WS IAM·로그·서비스·공유 접근/Service Connect 범위. ALB route/target group은 기존처럼 항상 유지 |
| `be_access` | `parameter_arns` map에 기존 `be_runtime.environment`의 각 SSM ARN을 **값 없이** 옮김. `secrets`, `kms_key_arns`는 기존 ARN 참조 유지 |
| `ai_access` | 이전 `ai_runtime`에서 ARN-only `secrets`, `kms_key_arns`, `additional_execution_secret_arns`만 이전 |
| `ws_access` | 이전 `ws_runtime`에서 ARN-only `secrets`, `kms_key_arns`만 이전 |

ARN map의 key는 권한 참조용 식별자이며 환경 내용을 생성하지 않는다. Secret 참조에는 JSON key/version selector를 허용하되 IAM Resource에는 원본 secret ARN만 사용한다. Secret 컨테이너 ARN도 허용 정책에 유지한다. Terraform은 Secret/SSM 값을 조회하거나 새 version을 발행하지 않는다. `config_references`와 `deployment_infrastructure`는 ARN/역할/로그/ECR 등 인프라 정보만 제공한다.

삭제된 `be_secret_values`, `ai_secret_values`, `be_secret_version`, `*_runtime.environment`, 이미지·아키텍처·원하는 태스크 수는 외부 배포 소유다. 이전 `*_deployment` 객체는 제거됐다. 별도 root인 `cloudwatch/` 입력과 섞지 않는다. NAT 하나를 두 AZ가 공유하는 기존 네트워크 구조와 ALB/SG/DB 설정은 유지한다.

SG와 접근 규칙은 각 소유 리소스의 `security.tf`에서 함께 관리한다. 서비스 간 연결에는 상대 SG ID와 포트만 전달한다. DB 종류를 고르는 선택 변수는 사용하지 않는다.

| 파일 | 관리하는 접근 규칙 |
| --- | --- |
| `alb/security.tf` | HTTP·HTTPS 수신, BE·WS로 송신 |
| `ecs/service/be/security.tf` | ALB에서 BE로 수신, BE 송신 |
| `ecs/service/ws/security.tf` | ALB에서 WS로 수신, WS 송신 |
| `ecs/service/ai/security.tf` | BE·WS에서 AI로 수신, AI 송신 |
| `database/security.tf` | MySQL은 BE·WS, PostgreSQL은 BE·AI 접근 |

V1 네트워크를 연결하면 기존 V1 MySQL의 BE·WS 접근과 V1 PostgreSQL의 AI 접근도 `database/security.tf`에서 관리한다. V1 SG 자체는 외부 참조로 유지한다. WS 서비스를 비활성화해도 기존 SG와 접근 규칙은 유지한다.

`migrations.tf`는 기존 루트 규칙 13개의 주소를 소유 모듈로 옮긴다. 기존 state에 적용할 때 규칙 ID를 유지하기 위한 `moved` 선언이므로 전환 중 삭제하지 않는다. 오프라인 검증은 `python3 scripts/check_terraform.py`로 실행한다.
