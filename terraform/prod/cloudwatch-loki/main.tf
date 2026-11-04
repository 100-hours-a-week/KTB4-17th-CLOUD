provider "aws" {
  region              = "ap-northeast-2"
  allowed_account_ids = ["975779326240"]
}

data "aws_instance" "loki" {
  instance_id = var.loki_instance_id
}

data "aws_subnet" "loki" {
  id = data.aws_instance.loki.subnet_id
}

module "cloudwatch_loki" {
  source = "./forwarder"

  name                   = "star23-prod-cloudwatch-loki"
  vpc_id                 = data.aws_subnet.loki.vpc_id
  subnet_ids             = [data.aws_instance.loki.subnet_id]
  loki_security_group_id = var.loki_security_group_id
  loki_write_address     = "http://${data.aws_instance.loki.private_ip}:3100/loki/api/v1/push"
  lambda_zip_path        = "${path.module}/dist/lambda-promtail-v1.0.1.zip"

  # This account has a concurrency quota of 10; reserved concurrency is unavailable.
  enable_dlq           = var.enable_failure_queue
  reserved_concurrency = -1
  extra_labels         = { cluster = "star23-ecs-cluster" }
  tags                 = { project = "star23", managed_by = "terraform" }
}
