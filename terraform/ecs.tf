resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-ecs-cluster"

  tags = {
    Name = "${local.name_prefix}-ecs-cluster"
  }
}