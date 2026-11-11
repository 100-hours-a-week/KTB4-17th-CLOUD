# V2 인프라

독립 backend `prod/terraform.tfstate`에서 V2 네트워크·ALB·ECS·RDS·IAM을 관리한다. CloudFront·공통 S3·ECR은 [common](../common/README.md)이 소유하며 `common.tf`에서 필요한 출력만 읽는다. 모니터링은 [cloudwatch](cloudwatch/README.md) 루트에서 관리하며 V1 네트워크 의존성은 없다.

## 입력과 실행

입력은 저장소 밖의 로컬 파일을 `-var-file`로 전달한다. 아래 경로는 실제 입력 파일의 절대 경로로 바꾼다.

```sh
terraform -chdir=terraform/v2 init -input=false -lockfile=readonly
terraform -chdir=terraform/v2 validate
terraform -chdir=terraform/v2 plan -input=false -lock-timeout=60s -var-file=/absolute/path/to/v2.tfvars.json
```

| 입력 | 용도 |
| --- | --- |
| `acm_certificate_arn` | ALB용 외부 인증서 ARN |
| `monitoring_security_group_id` | cloudwatch 루트의 `monitoring.security_group_id` 출력. 새 환경에서 모니터링 생성 전에는 명시적으로 null |
| `services_enabled` | 기본 true. 새 환경에서 외부 task 등록 전 단계에만 false |
| `task_definition_arns` | 생성할 서비스의 외부 task ARN: `be`, `ai`, `ws` |
| `ws_infrastructure` | `enabled`, `use_backend_config` 기본 true. WS 기반 자원 생성 여부와 BE 권한 참조 재사용 여부 |
| `be_access` | `parameter_arns`, `secrets`, `kms_key_arns`를 통한 ARN 기반 실행 권한 |
| `ai_access` | `secrets`, `kms_key_arns`, `additional_execution_secret_arns`를 통한 ARN 기반 실행 권한 |
| `ws_access` | `secrets`, `kms_key_arns`를 통한 ARN 기반 실행 권한 |

Secret·SSM 값과 task definition은 외부 배포가 관리한다. Secret ARN의 JSON key/version selector는 IAM 정책 생성 시 제거한다. `config_references`와 `deployment_infrastructure` 출력에는 ARN·역할·로그·ECR 등 인프라 정보만 포함한다.

ECS 서비스는 생성 시 외부 task ARN과 실행 수 0을 사용한다. 기존 서비스의 task revision과 실행 수는 외부 배포가 관리한다. 컨테이너 이름·포트는 BE `be:8080`, WS `ws:8080`, AI `ai:8000`이며 AI의 Service Connect port mapping 이름은 `ai-http`다.

## WS 옵션

`ws_infrastructure`의 두 옵션은 기본값이 true다. 기존 운영 환경에서는 현재 값을 유지한다.

| 옵션 | true | false |
| --- | --- | --- |
| `enabled` | WS IAM·로그를 생성하고, `services_enabled=true`이면 ECS 서비스도 생성 | WS IAM·로그·ECS 서비스를 생성하지 않음 |
| `use_backend_config` | BE·WS ARN을 병합해 읽기 권한 부여(WS 우선), KMS 키 합집합, 이미지 S3 접근 권한과 Service Connect 활성화 | WS에 지정한 ARN·KMS 권한만 사용, BE의 S3 권한과 Service Connect 연결을 추가하지 않음 |

`use_backend_config`는 `enabled=true`일 때 적용된다. 두 옵션 모두 SG·DB 접근 규칙·ALB 대상 그룹과 라우트를 제거하지 않는다.

## 네트워크와 접근 규칙

NAT 하나를 두 AZ가 공유한다. SG와 규칙은 각 소유 리소스의 `security.tf`에서 함께 관리하며 연결에는 상대 SG ID와 포트만 전달한다.

| 파일 | 관리하는 접근 |
| --- | --- |
| `alb/security.tf` | HTTP·HTTPS 수신, BE·WS로 송신 |
| `ecs/service/be/security.tf` | ALB·V2 모니터링에서 BE로 수신, BE 송신 |
| `ecs/service/ws/security.tf` | ALB·V2 모니터링에서 WS로 수신, WS 송신 |
| `ecs/service/ai/security.tf` | BE·WS에서 AI로 수신, AI 송신 |
| `database/security.tf` | MySQL은 BE·WS, PostgreSQL은 BE·AI 접근 |

모니터링은 BE·WS TCP 8080을 수집한다. WS 서비스를 비활성화해도 기존 SG와 DB 접근 규칙은 유지한다.

## 확인된 운영 설정 차이

현재 코드와 운영 환경의 차이 6건은 미적용 상태다. WS target group health 경로, RDS 2개의 backup retention(AWS 3일/코드 7일), public subnet 2개의 Kubernetes 태그, WS execution policy의 중복 statement 정리다. 전체 apply 전에 해당 차이를 검토한다.
