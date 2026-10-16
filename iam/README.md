# Terraform 실행 권한

`terraform-backend-settings.json`은 Terraform을 실행하는 IAM 사용자 `noel`에 추가할 정책이다.
서울 리전의 `/star23/prod/be/*` SSM 설정과 `star23/prod/be` Secret만 관리한다.
정책 파일 자체는 권한을 부여하지 않으므로 AWS IAM에서 사용자에게 연결해야 한다.
ECS 태스크의 실행 역할과 애플리케이션 역할은 `terraform/modules/ecs/iam.tf`가 별도로 관리한다.

`terraform-service-discovery.json`은 `star23-prod` Cloud Map 네임스페이스의 생성·관리 권한이다.
`noel`의 인라인 정책 `Star23TerraformServiceDiscovery`로 연결한다.
