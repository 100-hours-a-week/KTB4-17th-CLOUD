# ECS 클러스터와 서비스 간 통신 네임스페이스.

resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-ecs-cluster"

  tags = {
    Name = "${var.name_prefix}-ecs-cluster"
  }
}

resource "aws_service_discovery_http_namespace" "ecs" {
  name        = "${var.name_prefix}-prod"
  description = "Internal ECS service connections for star23 production"

  tags = {
    Name        = "${var.name_prefix}-prod"
    environment = "prod"
  }
}
