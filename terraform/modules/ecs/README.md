# 서비스 중심 ECS 모듈

루트 `terraform/main.tf`가 다음 모듈을 직접 조합한다. 이 디렉터리 자체는
실행 가능한 umbrella module이 아니다.

| 경로 | 소유권 / 입력 |
| --- | --- |
| `cluster` | 공용 ECS cluster, Service Connect HTTP namespace |
| `services/be` | BE task/service, 전용 SG·egress, 기존 BE IAM, 로그, SSM, 단일 공유 Secret/version |
| `services/ws` | WS task/service, S3 정책, BE config ARN 재사용 여부와 WS config/secret 참조, 전용 runtime 호출 |
| `services/ai` | AI task/service, AI config/secret ARN와 CI 추가 권한 참조, 전용 runtime 호출 |
| `runtime` | WS·AI에서 재사용하는 IAM·로그·전용 SG/egress 구현; 서비스마다 별도 인스턴스 |

각 서비스는 `subnet_ids`로 배치할 공유 subnet을 선택한다. VPC/subnet/NAT/route는
network 소유다. ALB와 DB 및 다른 서비스에 대한 SG 연결은 루트 `connections.tf`에서
서비스가 출력한 SG ID로 구성한다. ALB routing은 `module.alb`에만 남아 있다.
network는 서비스 출력에 의존하지 않으므로 순환하지 않는다.

`name_prefix`와 `environment`를 모듈 입력으로 받는다. 현재 실행 루트와 backend는
기존 prod이며, environment만 바꾸어 dev를 배포하는 구조가 아니다.

BE가 공유 Secret 객체와 version을 단독 소유한다. `ai_secret_values`도 이 소유자에
전달한다. WS는 BE의 `config_references` (SSM/Secret ARN)만 받아 자신의 참조·권한을
만들며, AI는 `ai_secrets`에 주어진 기존 ARN만 참조한다. 다른 서비스가 Secret을
중복 생성하거나 읽은 비밀값을 일반 Terraform 입력/출력으로 노출하지 않는다.

실제 값은 민감한 ephemeral 입력과 write-only provider 속성으로만 전달한다.
`be_secret_version`을 증가시켜 version을 갱신하는 작업은 이번 코드 단계에 포함하지 않는다.

서비스별 `ignore_changes = [task_definition]`을 유지한다. bootstrap task definition은
Terraform 소유지만 실제 서비스의 배포 리비전은 CI/CD 소유다. 기존 execution/task
역할 이름과 권한, 로그 경로·보관 기간, SG와 서비스 설정을 보존한다.

WS 비활성화 시 task/service·IAM·로그가 비활성화된다. 기존 network 모델에서 항상
소유했던 WS SG/egress 및 루트 연결 규칙은 계속 소유한다. 이는 staging 복원이 아니다.

[검증, 전체 주소/ID 표, 미실행 state-only 절차](../../../../docs/terraform-service-modules.md)를
검토해야 한다. 이 링크는 저장소 루트 기준으로 `docs/terraform-service-modules.md`다.
