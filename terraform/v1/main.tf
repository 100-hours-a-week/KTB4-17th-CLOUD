/**
 * Network
 *
 * 기존 V1 VPC·IGW·서브넷·라우팅 테이블을 dev에서 관리한다.
 * 공유 소비자가 남아 있으므로 네트워크 삭제는 보호한다.
 */
module "network" { source = "./network" }

/**
 * EC2
 */
module "ec2" {
  source             = "./ec2"
  subnet_ids         = module.network.subnet_ids
  security_group_ids = local.existing_security_group_ids
}

/**
 * Database EC2
 */
module "database" {
  source             = "./database"
  subnet_ids         = module.network.subnet_ids
  security_group_ids = local.existing_security_group_ids
}
