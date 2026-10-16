# ECS application runtime

BE, WebSocket, AI의 Task Definition·Service와 공통 클러스터를 관리한다.

- `main.tf`: 클러스터와 Service Connect 네임스페이스
- `be.tf`, `ws.tf`, `ai.tf`: 서비스별 실행 정의
- `configuration.tf`: BE의 SSM 일반 설정과 Secrets Manager 시크릿
- `iam.tf`: Execution Role과 앱 Task Role
- `logs.tf`: 서비스별 CloudWatch 로그 그룹과 30일 보관
- `variables*.tf`, `outputs.tf`: 모듈 입출력

네트워크와 ALB에서 준비된 서브넷·보안 그룹·Target Group을 입력받는다.
Terraform 실행자와 GitHub 배포 역할은 이 모듈에서 만들지 않는다.

Service의 `task_definition`은 최초 생성 후 CD가 관리한다.
CPU·환경변수·역할 등 Task Definition을 수정했다면 새 리비전을 CD에 인계해야 한다.
이미 실행 중인 Task에는 환경변수·시크릿 변경이 자동 반영되지 않는다.

BE 일반 설정은 SSM String, WS·AI 일반 설정은 Task Definition에 직접 전달한다.
비밀값은 ARN 참조 또는 BE의 ephemeral/write-only 입력으로 전달한다.
실제 값은 버전 관리되는 파일에 기록하지 않는다.

`ws_enabled`로 독립 WS 서비스를 선택한다. `ws_use_backend_config = true`면
BE의 SSM·Secret 설정과 S3 권한, Service Connect 클라이언트를 재사용한다.
비활성화하면 ALB의 `/ws` 요청은 BE로 전달된다.

AI 인증값은 `ai_secret_values`의 `AI_*` 키로 같은 Secret에 저장하고,
`ai_secrets`에서 해당 JSON 키의 ARN을 참조한다. 값을 바꿀 때는 `be_secret_version`을 올린다.
