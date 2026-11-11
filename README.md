# Terraform 인프라

버전별 인프라와 공통 자원을 독립된 state로 관리한다. 폴더 이름과 별개로 기존 backend key를 유지한다.

| 실행 루트 | backend key | 관리 대상 |
| --- | --- | --- |
| [`terraform/common`](terraform/common/README.md) | `common/terraform.tfstate` | 공통 CloudFront·S3·ECR |
| [`terraform/v1`](terraform/v1/README.md) | `dev/terraform.tfstate` | V1 EC2·네트워크 |
| [`terraform/v2`](terraform/v2/README.md) | `prod/terraform.tfstate` | V2 네트워크·ALB·ECS·RDS·IAM |
| [`terraform/v2/cloudwatch`](terraform/v2/cloudwatch/README.md) | `prod/cloudwatch-loki/terraform.tfstate` | V2 모니터링 EC2·SG·로그 전달 기반 |

## 관리 범위

| Terraform으로 관리 | 외부 배포·운영에서 관리 |
| --- | --- |
| VPC·subnet·라우팅·NAT·SG | — |
| EC2·EBS·ALB·대상 그룹 | 서버 프로그램 설치·앱 배포 |
| ECS cluster·service·Service Connect 네트워크 | Task definition·컨테이너 이미지·실행 수 |
| RDS·스토리지·백업·접근 규칙 | 테이블·스키마·데이터 |
| S3 버킷·ECR 저장소·접근 정책 | 업로드 파일·컨테이너 이미지 |
| IAM 역할·정책·Secret 저장소 | 실제 비밀번호·토큰·SSM 앱 설정값 |
| 로그 전달 IAM·SG·로그 그룹·SQS·호출 권한·구독·재시도 설정 | Lambda 함수·코드·runtime·환경·VPC/DLQ 부착 |

입력 파일은 저장소 밖에서 관리하고 `-var-file`로 전달한다. 앱 연동 입력은 외부 task ARN과 Secret·SSM·KMS ARN으로 제한하며 실제 앱 설정값은 읽거나 발행하지 않는다.

## 새 환경 구성 순서

1. 공통 자원을 준비하고, 버전별 루트에 `services_enabled=false`로 네트워크·IAM·로그 등 기반 자원을 생성한다. `deployment_infrastructure` 출력은 외부 배포에 필요한 ARN과 네트워크 정보를 제공한다.
2. 외부 배포가 이미지·설정값·task definition을 준비한다. 등록한 ARN을 `task_definition_arns`에 전달하고 `services_enabled=true`로 ECS 서비스를 생성한다. 최초 실행 수는 0이며 이후 task revision과 실행 수는 외부 배포가 관리한다.
3. 모니터링·로그 전달 기반은 [별도 루트의 순서](terraform/v2/cloudwatch/README.md)를 따른다.

기존 운영 환경에서는 `services_enabled=true`를 유지한다. WS 사용 여부와 서비스별 입력은 [V2 안내](terraform/v2/README.md)를 따른다. 공통 자원은 버전별 destroy 대상에 포함하지 않는다.

## 실행

Terraform >=1.11.0, AWS provider ~>6.0을 사용하며 각 루트의 lockfile을 따른다. 실행할 루트에서 먼저 `init`·`validate`를 수행하고 `plan`을 검토한다. 구체적인 입력과 명령은 각 루트 README에 있다.

```sh
terraform fmt -check -recursive terraform
terraform -chdir=terraform/common init -input=false -lockfile=readonly
terraform -chdir=terraform/common validate
terraform -chdir=terraform/common plan -input=false -lock-timeout=60s
```
