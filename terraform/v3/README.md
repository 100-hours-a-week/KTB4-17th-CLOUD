# V3 인프라

기존 AWS 자원을 새로 만들지 않고 관리한다. 독립 backend는 `v3/terraform.tfstate`이며, VPC·NAT·공유 subnet·ECS SG는 V2의 `prod/terraform.tfstate` 출력을 읽는다.

| 폴더 | 관리 범위 |
| --- | --- |
| `eks/` | EKS cluster·managed nodegroup·AWS managed addon·접근 권한·IAM/OIDC·Pod Identity·전용 subnet·기존 NAT 경로와 Kafka/Redis 접근 규칙 |
| `database/` | 기존 MySQL/PostgreSQL·DB subnet group·SG·ECS/EKS/Bastion/기존 마이그레이션 접근 규칙 |

V3는 총 67개 Terraform 자원을 관리한다. V2의 DB 관련 10개 state 기록을 옮기고, 기존 EKS·권한·네트워크·추가 DB 규칙 57개를 import했다. 기존 DB 식별자와 태그의 `v2`는 유지한다. V2의 `database/` 코드는 기록용으로 남아 있지만 루트에서는 호출하지 않는다.

## 관리 경계

AWS 관리 애드온은 CoreDNS·VPC CNI·kube-proxy·Pod Identity agent 네 개다. CNI의 Pod Identity는 addon 내부에서 관리하고, 다른 연결 7개는 독립 자원으로 관리한다.

EKS가 생성하는 EC2·ASG·Launch Template·instance profile·cluster SG와 Kubernetes controller가 생성하는 ALB·대상 그룹은 별도로 소유하지 않는다. 노드의 최소·최대 용량은 Terraform, 실행 노드 수는 기존 Cluster Autoscaler가 관리한다.

Helm·Argo CD·Deployment·Service·Ingress·ServiceAccount 배포, 컨테이너 이미지, 서버 프로그램, DB 스키마·데이터, Secret·SSM 실제 값은 여기서 관리하지 않는다. Controller·ESO·앱에 필요한 AWS 역할과 ARN 기반 권한 연결만 관리한다.

## 공유 의존성

V3 EKS는 V2 VPC·NAT·public subnet을 사용하며 RDS는 V2 data subnet에 있다. 기존 V2 ECS도 같은 RDS를 사용한다. 따라서 V2 네트워크를 독립적으로 삭제할 수는 없다.

`connections.tf`는 외부 Bastion·마이그레이션 SG를 조회만 한다. Kafka/Redis EC2와 그 SG도 외부 소유를 유지하고, V3가 사용하는 수신 규칙만 `eks/security.tf`에 둔다. V2는 DB 연결 정보를 AWS에서 조회하므로 두 state가 서로 역참조하지 않는다.

## 실행

```sh
terraform -chdir=terraform/v3 init -input=false -lockfile=readonly
terraform -chdir=terraform/v3 validate
terraform -chdir=terraform/v3 plan -input=false -lock-timeout=60s
```

AWS 계정은 `975779326240`, 리전은 `ap-northeast-2`로 제한한다. V3 루트에 앱 설정이나 실제 비밀번호 입력은 필요하지 않다. 기존 AWS 설정을 기준으로 편입했으며 API endpoint 접근 범위·클러스터 로그·DB 백업 보관일 같은 운영 설정도 기존 값을 유지한다.
