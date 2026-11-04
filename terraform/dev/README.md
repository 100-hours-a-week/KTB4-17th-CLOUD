# 개발 인프라

독립 실행 루트이며 backend는 `dev/terraform.tfstate`다. 기존 V1 네트워크·SG·EIP·IAM은 참조하고 EC2 3개만 소유한다. 운영 루트와 합쳐 실행하지 않는다.

```sh
terraform -chdir=terraform/dev init -input=false -lockfile=readonly
terraform -chdir=terraform/dev validate
terraform -chdir=terraform/dev plan -input=false -lock-timeout=60s
```

`versions.tf`와 lockfile은 실행 루트의 Terraform/provider 버전을 고정한다. child는 기존 파일에 `hashicorp/aws` 요구사항을 선언하고 루트 provider 설정을 상속한다. state·plan은 저장소 밖 권한 제한 경로에 보관한다.
