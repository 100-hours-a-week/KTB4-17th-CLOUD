# V1 dev EC2

`modules/ec2`는 기존 app/data/messaging EC2 3대의 독립 dev 코드다. backend는 같은 bucket의 `dev/terraform.tfstate`이며 아직 원격 state를 생성하거나 리소스를 편입하지 않았다.

현재 state가 없는 상태에서 이 루트에 일반 plan을 하면 생성 제안이 나타날 수 있다. 먼저 [정확한 소유권·private adoption preview와 승인 경계](../../docs/terraform-environment-separation.md)를 확인한다. apply/import 실행은 이번 작업에 포함되지 않는다. 기존 SG·VPC·IAM·EIP는 참조만 하며 별도로 소유하지 않는다.
