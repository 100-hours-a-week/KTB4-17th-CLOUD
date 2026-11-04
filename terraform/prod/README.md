# 운영 인프라

`prod/terraform.tfstate`를 사용하는 독립 실행 루트다. 네트워크·ALB·RDS·스토리지·CDN·ECS를 조합하고 교차 SG 규칙은 `connections.tf`에서 연결한다. V1 VPC/DB/SG와 기존 EIP·IAM의 공유/외부 소유 범위를 유지한다. 로그 전달은 별도 `cloudwatch/` 루트다.

```sh
terraform -chdir=terraform/prod init -input=false -lockfile=readonly
terraform -chdir=terraform/prod validate
```

plan에는 저장소 밖 입력 파일을 `-var-file`로 명시한다. 하위 디렉터리의 tfvars는 루트에 자동 적용되지 않는다. 비밀값·state·plan·ZIP은 커밋하지 않는다.

- `acm_certificate_arn`, `v1_database_network`: 외부 인증서와 기존 V1 네트워크/DB SG 참조.
- `be_deployment`, `ai_deployment`: 초기 이미지 `image_tag`, 선택적 `cpu_architecture`(X86_64), `desired_count`(2). 이후 task revision은 CI가 관리한다.
- `ws_deployment`: `image_uri`, 같은 아키텍처/태스크 수, `enabled`, `use_backend_config`. 운영 기본값은 실제 운영처럼 두 bool 모두 true이며 명시적으로 비활성화할 수 있다.
- 서비스별 `*_runtime`: 비밀이 아닌 `environment`, 외부 secret ARN `secrets`, `kms_key_arns`. AI는 CI revision용 `additional_execution_secret_arns`도 지원한다. 실제 값은 외부에서 전달하며 child 검증을 거친다. BE 일반 설정은 계속 SSM 객체로 관리한다.
- `ai_database_access`, `ws_database_access`: mysql/postgres 접근 범위.
- `be_secret_values`, `ai_secret_values`: 검증된 sensitive/ephemeral 런타임 입력. 비밀값은 런타임에만 주입한다. `be_secret_version`은 실제 비밀 교체 시 증가시킨다.

`prod` 라벨과 고정 네트워크 사실은 루트 locals에, 서비스의 포트/헬스 경로/AI timeout은 각 서비스 `configuration.tf`에 있다. 포트 출력은 ALB·SG·Service Connect에 공유하며 서비스 준비 완료를 기다리지 않는다. DB 계정 기본값은 database 모듈 소유다. 태스크 수·이미지·아키텍처·WS 활성화·외부 설정/권한 등 운영 입력은 유지한다.

`storage/ecr.tf`는 ECR, `storage/s3.tf`는 S3를 관리하며 `module.storage`는 유지한다. 각 폴더에 versions.tf가 필요한 것은 아니다. 독립 실행 루트 3곳만 Terraform >=1.11/AWS ~>6.0과 lock 6.71.0을 유지하고 child는 기존 파일에 `required_providers`의 `hashicorp/aws`를 선언한다. 계정 allowlist와 region 설정은 루트에 남는다.

Secret/version → AI task → healthy AI service → BE service 순서와 서비스 노드에 한정된 트래픽/네트워크 준비 조건을 유지한다. NAT 1개를 두 AZ가 공유하므로 장애와 AZ 간 트래픽 영향을 고려한다.
