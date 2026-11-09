# Terraform 인프라 소유권

Terraform 실행자용 추가 권한 템플릿은 [bootstrap/iam](bootstrap/iam/README.md)에 보관한다. 인프라 리소스의 IAM 역할·정책은 각 Terraform 모듈에서 관리한다.

활성 실행 루트와 state는 아래처럼 분리한다. 공통 자원은 버전별 destroy 대상에 포함하지 않는다.

| 실행 루트 | backend key | 소유 범위 |
| --- | --- | --- |
| [`terraform/common`](terraform/common/README.md) | `common/terraform.tfstate` | 공통 CloudFront·S3·ECR |
| [`terraform/v1`](terraform/v1/README.md) | `dev/terraform.tfstate` | 기존 V1 EC2·네트워크 |
| [`terraform/v2`](terraform/v2/README.md) | `prod/terraform.tfstate` | V2 네트워크·ALB·ECS·DB·IAM |
| [`terraform/v2/cloudwatch`](terraform/v2/cloudwatch/README.md) | `prod/cloudwatch-loki/terraform.tfstate` | 로그 전달 인프라 |

폴더 이름을 바꾼 V1·V2는 기존 backend key를 유지한다. V3를 추가할 때도 공통 자원은 다시 생성하지 않고 common 출력을 참조한다.

| Terraform | 외부 배포/운영 |
| --- | --- |
| VPC·subnet·routes·NAT·SG, EC2/EBS, ALB·target groups | 서버 프로그램 설치 |
| ECS cluster·서비스 shell·IAM·로그·Service Connect 네트워크 | BE/AI/WS task definition 전체, 이미지·CPU/메모리·아키텍처·컨테이너 health command·환경·실행 수·최초 실행·후속 배포 |
| RDS instance·storage·backup·접근, RDS의 AWS 관리 master credential 설정 | schema·table·data, 실제 password/token 값과 발행/교체 |
| S3 bucket·ECR repository·접근 정책, IAM, Secret 컨테이너 | 업로드 파일·이미지, SSM 애플리케이션 값·Secret version |
| Lambda용 IAM·SG·로그·SQS·호출 권한·구독·비동기 retry 설정 | Promtail Lambda 함수 lifecycle 전체, ZIP·프로그램 버전·runtime·환경·relabel 설정·VPC/DLQ 부착 |

Task definition도 AWS 리소스지만 사용자가 정한 경계에 따라 CI/CD가 소유한다. `ignore_changes`만으로 task definition을 계속 등록하는 구조는 사용하지 않는다. 서비스 shell의 `task_definition`, `desired_count`만 배포 소유 필드라 무시하며, 생성 시에도 외부 ARN과 실행 수 0만 사용한다. 기존 서비스는 실제 revision과 실행 수를 유지한다. 서비스 삭제 방지는 bootstrap 플래그의 잘못된 사용을 차단한다.

## 완료한 state 소유권 이관

2026-11-09 계정과 리전을 확인하고, 원격 state 백업·네 곳의 잠금·원본 version 대조를 거쳐 아래 내용을 반영했다. 실제 인프라 설정은 변경하지 않았다.

- CloudFront 1개, S3 2개, ECR 2개를 prod state에서 common state로 이동했다.
- V1 네트워크 9개를 기존 ID로 dev state에 편입했다.
- SG 규칙 13개, BE·AI 서비스 2개, Lambda 비동기 호출 설정 1개의 주소를 옮기고 ID를 유지했다.
- 앱 SSM 49개, Secret version 1개, task definition 3개, Lambda 함수 1개는 삭제 없이 Terraform 관리에서 해제했다. 실제 값·프로그램·배포는 외부 관리 범위다.

각 원격 state를 다시 읽어 결과를 검증한 뒤 일회성 `moved`·`import`·`removed` 선언을 모두 제거했다. 유지하는 자원의 선언과 삭제 보호는 남긴다. 예전 state를 그대로 다시 연결하기 위한 이관 선언은 현재 코드에 포함하지 않는다.

운영 입력은 [V2 계약](terraform/v2/README.md)에 맞춰 저장소 밖에 보관한다. 현재 task revision과 SSM/Secret/KMS의 ARN만 전달하며 Terraform으로 실제 설정값을 읽지 않는다. 이관 시 확인한 V2의 기존 설정 차이 6건은 적용하지 않았다. RDS 백업 기간, WS 헬스체크, public subnet의 Kubernetes 태그, WS IAM 정책 차이는 별도로 검토한다.

## 새로운 환경의 단계별 bootstrap

운영 기존 상태에 bootstrap 플래그를 적용하지 않는다. 아래는 앞으로의 작업 순서 계약이며 이번 작업에서 실행하지 않았다.

1. 새 prod backend와 인증서/기존 네트워크 참조를 준비하고 `services_enabled=false`로 전체 인프라를 생성한다. WS를 쓸 경우 `ws_infrastructure.enabled=true`를 이 단계부터 유지해 IAM·로그를 먼저 만든다. ALB route/target group은 스위치와 무관하게 기존 구조로 유지한다. 서비스와 task definition은 아직 없다. `deployment_infrastructure` 출력으로 cluster·namespace·subnet·execution/task role·로그·ECR·Secret 컨테이너 ARN을 전달한다.
2. 기존 외부 배포 도구가 이미지 게시, SSM 값과 Secret 실제 값 발행, task definition 등록을 수행한다. 출력의 역할·로그 그룹을 사용하고 아래 서비스별 포트 계약을 충족한다. Terraform 입력에는 실제 값이나 환경 map을 넣지 않는다.
3. 등록한 세 task ARN을 `task_definition_arns`에 전달하고 `services_enabled=true`로 shell을 생성한다. disabled WS는 ARN이 없어도 된다. 모든 shell의 초기 `desired_count=0`이므로 Terraform은 앱을 시작하지 않는다. 이후 외부 배포가 AI→BE/WS 준비 순서로 task revision과 실행 수를 설정하고 readiness를 확인한다. 이후 revision/실행 수는 CI/CD에서 계속 관리한다.
4. 독립 로그 루트는 [로그 bootstrap](terraform/v2/cloudwatch/README.md) 순서로 인프라→외부 Lambda 생성→구독 연결을 진행한다. 빈 ZIP·더미 이미지·provisioner는 없다.

BE: 컨테이너 `be`, 포트 8080, ALB health `/actuator/health`. WS: `ws`, 포트/port mapping 이름 `ws` 8080, 같은 ALB health. AI: `ai`, `ai-http` 포트 8000, Service Connect `ai`, HTTP health `/health`, 요청 timeout 150초. 외부 task는 Fargate/awsvpc와 이 이름·포트를 충족해야 한다. container health 명령, 로그 `awslogs` 설정과 runtime 내용은 배포 저장소가 관리한다.

## 검증

```sh
terraform fmt -check -recursive terraform/common
terraform -chdir=terraform/common init -input=false -lockfile=readonly
terraform -chdir=terraform/common validate
terraform -chdir=terraform/v1 test
terraform -chdir=terraform/v2 test
```

각 실행 루트는 최초 실행 시 해당 디렉터리에서 init을 수행한다. HCL 테스트는 mock provider의 plan으로 외부 참조와 선택적 구성 경로를 검증한다. 실제 환경의 drift와 권한은 별도 읽기 전용 plan으로 확인한다. 이관에서는 common·V1 및 기존 로그 전달 구성의 무변경 계획과 모든 유지 대상 ID를 확인했다. V2 전체 plan에는 위에 적은 기존 설정 차이가 남아 있어 전체 apply는 실행하지 않았다.

Terraform 요구사항은 >=1.11.0, AWS provider는 ~>6.0 / lock **6.71.0**을 유지한다. 실제 state·plan·비밀값·패키지는 저장소에 넣지 않는다. 원격 state 백업과 이관 작업 파일은 저장소 밖 권한 제한 경로에 보관했다.

모니터링 수집기·대시보드·Docker Compose와 Lambda 패키지 배포 소스는 외부에서 관리한다. Terraform은 호스트·네트워크·IAM·로그·호출 권한·구독 등 인프라 자원을 관리한다. 기존 backend key와 AWS 리소스 이름의 `cloudwatch-loki`는 소유권 연결을 위해 유지한다.
