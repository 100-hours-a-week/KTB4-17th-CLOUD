provider "aws" {
  region              = "ap-northeast-2"
  allowed_account_ids = ["975779326240"]
}

/**
 * V2 monitoring host
 */
module "monitoring" {
  source                             = "./monitoring"
  ami_id                             = var.monitoring_ami_id
  vpc_id                             = var.monitoring_vpc_id
  subnet_id                          = var.monitoring_subnet_id
  ssh_cidrs                          = var.monitoring_ssh_cidrs
  grafana_admin_cidrs                = var.monitoring_grafana_admin_cidrs
  lambda_forwarder_security_group_id = module.cloudwatch_loki.security_group_id
}

/**
 * Log forwarding
 *
 * 외부 Lambda의 실행 기반과 CloudWatch 로그 구독을 구성한다.
 */
module "cloudwatch_loki" {
  source = "./forwarder"

  name                   = "star23-prod-cloudwatch-loki"
  vpc_id                 = var.monitoring_vpc_id
  subnet_ids             = [module.monitoring.subnet_id]
  loki_security_group_id = module.monitoring.security_group_id

  enable_function_connections = var.enable_function_connections
  enable_dlq                  = var.enable_failure_queue
  tags                        = { project = "star23", managed_by = "terraform" }
}
