# Terraform 인프라 소유권

활성 실행 루트는 `terraform/dev`, `terraform/prod`, `terraform/prod/cloudwatch` 세 곳이다. 로그 전달은 prod와 별도 backend다. 운영 반영은 이 PR의 범위가 아니며 이관 선언도 아직 적용하지 않았다.

| Terraform | 외부 배포/운영 |
| --- | --- |
| VPC·subnet·routes·NAT·SG, EC2/EBS, ALB·target groups | 서버 프로그램 설치 |
| ECS cluster·서비스 shell·IAM·로그·Service Connect 네트워크 | BE/AI/WS task definition 전체, 이미지·CPU/메모리·아키텍처·컨테이너 health command·환경·실행 수·최초 실행·후속 배포 |
| RDS instance·storage·backup·접근, RDS의 AWS 관리 master credential 설정 | schema·table·data, 실제 password/token 값과 발행/교체 |
| S3 bucket·ECR repository·접근 정책, IAM, Secret 컨테이너 | 업로드 파일·이미지, SSM 애플리케이션 값·Secret version |
| Lambda용 IAM·SG·로그·SQS·호출 권한·구독·비동기 retry 설정 | Promtail Lambda 함수 lifecycle 전체, ZIP·프로그램 버전·runtime·환경·relabel 설정·VPC/DLQ 부착 |

Task definition도 AWS 리소스지만 사용자가 정한 경계에 따라 CI/CD가 소유한다. `ignore_changes`만으로 task definition을 계속 등록하는 구조는 사용하지 않는다. 서비스 shell의 `task_definition`, `desired_count`만 배포 소유 필드라 무시하며, 생성 시에도 외부 ARN과 실행 수 0만 사용한다. 기존 서비스는 실제 revision과 실행 수를 유지한다. 서비스 삭제 방지는 bootstrap 플래그의 잘못된 사용을 차단한다.

## 기존 환경의 검토 가능한 이관

1. 기존 배포 저장소/운영 설정에서 현재 BE/AI/WS task ARN(리비전 포함), SSM/Secret ARN, KMS ARN을 확인한다. Terraform으로 secret 값을 읽지 않는다. 입력은 [prod 계약](terraform/prod/README.md)에 맞춰 저장소 밖에서 준비한다. 기존 WS 인프라·공유권한 스위치를 보존한다.
2. 기존 backend key, module 주소, 리소스 이름은 유지한다. BE/AI 서비스는 singleton→`[0]`, Lambda 비동기 호출 설정은 singleton→`[0]`의 `moved` 선언으로 주소만 연결한다. WS는 기존 `[0]`를 유지한다.
3. `removed` + `destroy=false` 대상은 `module.be.aws_ssm_parameter.be_config`의 **모든 key**, `module.be.aws_secretsmanager_secret_version.be`, BE/AI/WS task definition(WS의 모든 instance), `module.cloudwatch_loki.aws_lambda_function.forwarder`다. 운영자가 나중에 검토·반영할 때 AWS 삭제 없이 Terraform 상태에서만 소유권을 내려놓는다. 선언은 이전 상태의 후속 이관을 위해 보존한다. state CLI 수정이나 import는 필요하지 않다.
4. 향후 승인된 운영 작업에서 각 루트의 private read-only plan을 검토한다. 위 대상은 `forget`, 서비스는 revision/실행 수 변경 없음, 기타 허용 인프라는 의도한 범위만 나와야 한다. 예상하지 못한 delete/replace/start가 있으면 반영하지 않는다. ARN-only 권한 목록은 기존 ARN을 누락하지 않게 옮긴다.
5. 외부 배포는 기존 ARN/함수 이름을 인계받아 기존 배포 절차를 이어간다. 이 PR은 새 배포 기능, 대체 소유자의 실시간 활성화, 재배포, 상태 반영을 요구하거나 실행하지 않는다. 기존 함수/Secret/SSM/task revision/서비스는 동작을 계속한다.

## 새로운 환경의 단계별 bootstrap

운영 기존 상태에 bootstrap 플래그를 적용하지 않는다. 아래는 앞으로의 작업 순서 계약이며 이번 작업에서 실행하지 않았다.

1. 새 prod backend와 인증서/기존 네트워크 참조를 준비하고 `services_enabled=false`로 전체 인프라를 생성한다. WS를 쓸 경우 `ws_infrastructure.enabled=true`를 이 단계부터 유지해 IAM·로그를 먼저 만든다. ALB route/target group은 스위치와 무관하게 기존 구조로 유지한다. 서비스와 task definition은 아직 없다. `deployment_infrastructure` 출력으로 cluster·namespace·subnet·execution/task role·로그·ECR·Secret 컨테이너 ARN을 전달한다.
2. 기존 외부 배포 도구가 이미지 게시, SSM 값과 Secret 실제 값 발행, task definition 등록을 수행한다. 출력의 역할·로그 그룹을 사용하고 아래 서비스별 포트 계약을 충족한다. Terraform 입력에는 실제 값이나 환경 map을 넣지 않는다.
3. 등록한 세 task ARN을 `task_definition_arns`에 전달하고 `services_enabled=true`로 shell을 생성한다. disabled WS는 ARN이 없어도 된다. 모든 shell의 초기 `desired_count=0`이므로 Terraform은 앱을 시작하지 않는다. 이후 외부 배포가 AI→BE/WS 준비 순서로 task revision과 실행 수를 설정하고 readiness를 확인한다. 이후 revision/실행 수는 CI/CD에서 계속 관리한다.
4. 독립 로그 루트는 [로그 bootstrap](terraform/prod/cloudwatch/README.md) 순서로 인프라→외부 Lambda 생성→구독 연결을 진행한다. 빈 ZIP·더미 이미지·provisioner는 없다.

BE: 컨테이너 `be`, 포트 8080, ALB health `/actuator/health`. WS: `ws`, 포트/port mapping 이름 `ws` 8080, 같은 ALB health. AI: `ai`, `ai-http` 포트 8000, Service Connect `ai`, HTTP health `/health`, 요청 timeout 150초. 외부 task는 Fargate/awsvpc와 이 이름·포트를 충족해야 한다. container health 명령, 로그 `awslogs` 설정과 runtime 내용은 배포 저장소가 관리한다.

## 오프라인 검증

```sh
terraform fmt -check -recursive terraform
python3 scripts/check_terraform.py
```

테스트 명령은 세 활성 루트 모두 backend 비활성 init(`-lockfile=readonly`), validate, Terraform mock-provider **plan 전용** 테스트를 실행한다. 전체 resource change를 검사해 금지 리소스 부재, bootstrap 시 앱/구독 미생성, 외부 ARN 연결, 허용 인프라 보존을 확인한다. 실제 AWS provider를 사용하는 가상 상태 fixture는 production의 removed/moved/service HCL을 가져와 네트워크 참조만 fixture 상수로 바꾼다. 모든 이관 대상의 `forget`, 기존 서비스 revision 99/실행 수 5의 no-op, 기존 서비스 비활성화 거부를 검사한다. fixture는 실제 운영 상태가 아니며 임시 디렉터리에서 삭제된다. 테스트는 apply/state 편집 명령/AWS API 호출을 사용하지 않는다.

Terraform 요구사항은 >=1.11.0, AWS provider는 ~>6.0 / lock **6.71.0**을 유지한다. `removed` 비파괴 이관은 [Terraform 1.7부터 지원](https://developer.hashicorp.com/terraform/tutorials/state/state-cli)한다. 현재 설치된 Terraform 1.16.4와 잠긴 provider로 검증한다. [removed 공식 계약](https://developer.hashicorp.com/terraform/language/block/removed), [서비스의 외부 scaling 무시](https://registry.terraform.io/providers/hashicorp/aws/6.71.0/docs/resources/ecs_service)를 참조한다.

운영 read-only plan은 이 실행에서 수행하지 않았다. 오프라인 fixture는 운영 drift·실제 IAM/배포 권한·AWS API 수용 여부를 증명하지 않는다. 운영 반영 전 private plan과 배포 도구의 계약 확인이 남아 있다. 비밀값/state/plan/ZIP은 출력·커밋하지 않는다. `terraform/terraform.tfvars`는 prod에서 자동 로드되지 않는다. `-var-file`로 활성 루트의 외부 입력을 명시한다.

원본 작업 디렉터리의 비추적 `iam/terraform-rds-encryption.json`, `monitoring/`, `terraform/.terraform.lock.hcl`, `terraform/cloudwatch-loki/`, `terraform/import_ws_ai_ingress.tf`, `terraform/modules/`는 사용자 자료로 보존했다. 특히 비추적 `cloudwatch-loki`/`modules`의 이전 프로그램 관리 코드는 이 PR의 활성 tracked 루트에 포함되지 않으며 별도 정리 대상이다. 원본 루트 전체를 재귀 실행해 이 파일들을 합치지 않는다.
