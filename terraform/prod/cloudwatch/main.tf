provider "aws" {
  region              = "ap-northeast-2"
  allowed_account_ids = ["975779326240"]
}

/**
 * Loki references
 */
data "aws_instance" "loki" {
  instance_id = var.loki_instance_id
}

data "aws_subnet" "loki" {
  id = data.aws_instance.loki.subnet_id
}

/**
 * Log forwarding
 *
 * 외부 Lambda의 실행 기반과 CloudWatch 로그 구독을 구성한다.
 */
module "cloudwatch_loki" {
  source = "./forwarder"

  name                   = "star23-prod-cloudwatch-loki"
  vpc_id                 = data.aws_subnet.loki.vpc_id
  subnet_ids             = [data.aws_instance.loki.subnet_id]
  loki_security_group_id = var.loki_security_group_id

  enable_function_connections = var.enable_function_connections
  enable_dlq                  = var.enable_failure_queue
  tags                        = { project = "star23", managed_by = "terraform" }
}
