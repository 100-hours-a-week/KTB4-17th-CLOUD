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
  source              = "./ec2"
  app_subnet_id       = module.network.subnet_ids["subnet-046d61dd64b873264"]
  messaging_subnet_id = module.network.subnet_ids["subnet-0d6ff6e6460961e3c"]
  security_group_ids = {
    ssh = local.existing_security_group_ids.ssh
    app = local.existing_security_group_ids.app
  }
}

/**
 * Database EC2
 */
module "database" {
  source             = "./database"
  database_subnet_id = module.network.subnet_ids["subnet-046d61dd64b873264"]
  security_group_ids = {
    ssh      = local.existing_security_group_ids.ssh
    database = local.existing_security_group_ids.database
  }
}
