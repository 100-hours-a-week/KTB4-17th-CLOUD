/** Shared V2 network
 * VPC·NAT·기존 서비스 SG의 소유권은 V2에 유지한다.
 */
data "terraform_remote_state" "v2" {
  backend = "s3"

  config = {
    bucket = "star23-tfstate-975779326240"
    key    = "prod/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

/** EKS infrastructure
 * 기존 클러스터·노드 그룹·네트워크·실행 권한을 관리한다.
 */
module "eks" {
  source = "./eks"

  vpc_id         = data.terraform_remote_state.v2.outputs.network.vpc_id
  nat_gateway_id = data.terraform_remote_state.v2.outputs.network.nat_gateway_id
}

/** Shared databases
 * 기존 v2 DB 이름을 유지하고, 관리 소유권만 V3로 옮긴다.
 */
module "database" {
  source = "./database"

  name_prefix = "star23"
  environment = "prod"
  vpc_version = "v2"

  vpc_id          = data.terraform_remote_state.v2.outputs.network.vpc_id
  data_subnet_ids = data.terraform_remote_state.v2.outputs.network.data_subnet_ids
  mysql_port      = 3306
  postgres_port   = 5432

  be_security_group_id        = data.terraform_remote_state.v2.outputs.ecs_security_group_ids.be
  ws_security_group_id        = data.terraform_remote_state.v2.outputs.ecs_security_group_ids.ws
  ai_security_group_id        = data.terraform_remote_state.v2.outputs.ecs_security_group_ids.ai
  eks_security_group_id       = module.eks.cluster_security_group_id
  bastion_security_group_id   = data.aws_security_group.bastion.id
  migration_security_group_id = data.aws_security_group.migration.id
}
