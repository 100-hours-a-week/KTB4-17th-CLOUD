# Terraform 실행 권한 참고

Terraform을 실행하는 사용자나 CI 역할에 필요한 일부 추가 권한을 기록한 정책 템플릿이다. 인프라를 새로 구성하거나 실행 주체를 바꿀 때 기존 권한과 함께 검토하는 용도로 보관한다. 이 디렉터리는 Terraform 실행 루트가 아니며, Terraform 코드가 이 JSON을 읽거나 자동으로 IAM에 연결하지 않는다.

| 정책 | 용도 |
| --- | --- |
| `terraform-service-discovery.json` | `star23-prod` Cloud Map 네임스페이스 생성·관리 |
| `terraform-rds-encryption.json` | 지정된 RDS·Secret용 KMS 키 조회, RDS 서비스용 grant, RDS 관리형 Secret 생성·태그 |

두 파일은 기존 계정 `975779326240`, 리전 `ap-northeast-2`, 네임스페이스·태그·KMS 키 ARN에 맞춰져 있다. 다른 환경에 사용할 때는 실제 대상과 필요한 작업을 다시 확인한다. 전체 실행 권한을 정의한 정책 묶음은 아니며, state 저장소와 EC2·IAM 등 나머지 권한은 별도로 관리한다.

필요한 정책은 권한 관리자가 실제 Terraform 실행 주체에 별도로 연결한다. 저장소에 JSON을 보관하는 것만으로 권한이 부여되거나, 파일을 삭제하는 것만으로 기존 AWS 권한이 회수되지는 않는다. [AWS IAM 정책과 권한](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html)을 참고한다.

애플리케이션이 실행 중 사용하는 ECS execution/task 역할은 [서비스별 IAM 코드](../../terraform/v2/ecs/service/)가 관리한다. 이 템플릿과 적용 대상이 다르다.

이전 `iam/terraform-backend-settings.json`은 앱 SSM 값과 Secret version의 읽기·쓰기·삭제 권한을 담고 있어 제거했다. 이름과 달리 Terraform state backend 권한 정책이 아니었다. 앱 설정값 발행·교체는 외부 배포/운영 주체가 관리하며, 이 정책 제거는 이미 연결된 AWS IAM 권한을 변경하지 않는다.
