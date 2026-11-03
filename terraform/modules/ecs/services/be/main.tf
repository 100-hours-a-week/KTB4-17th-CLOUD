resource "aws_ecs_task_definition" "be" {
  family                   = "${var.name_prefix}-be"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.be_cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = "be"
      image     = "${var.be_repository_url}:${var.be_image_tag}"
      essential = true

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.service.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      portMappings = [{
        name          = "http"
        containerPort = var.app_port
        protocol      = "tcp"
        appProtocol   = "http"
      }]

      secrets = [
        for name, value_from in local.be_environment_references : {
          name      = name
          valueFrom = value_from
        }
      ]
    }
  ])

  tags = {
    Name        = "${var.name_prefix}-be-task"
    environment = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_execution,
    aws_iam_role_policy.ecs_execution_secrets,
    aws_iam_role_policy.ecs_execution_secret_kms,
    aws_iam_role_policy.be_s3,
    aws_secretsmanager_secret_version.be
  ]
}

resource "aws_ecs_service" "be" {
  name                  = "${var.name_prefix}-be-service"
  cluster               = var.cluster_id
  task_definition       = aws_ecs_task_definition.be.arn
  launch_type           = "FARGATE"
  platform_version      = "LATEST"
  desired_count         = var.be_desired_count
  propagate_tags        = "SERVICE"
  wait_for_steady_state = true

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 120
  availability_zone_rebalancing      = "ENABLED"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets = var.subnet_ids

    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.be_target_group_arn
    container_name   = "be"
    container_port   = var.app_port
  }

  # BE 태스크는 Service Connect를 통해 ai라는 이름으로 AI 엔드포인트를 조회한다.
  service_connect_configuration {
    enabled   = true
    namespace = var.namespace_arn
  }

  tags = {
    Name        = "${var.name_prefix}-be-service"
    environment = var.environment
  }

  # 생성 후 리비전 업데이트는 CI/CD가 담당한다. Terraform이 배포된 버전을 되돌리지 않도록 한다.
  lifecycle {
    ignore_changes = [task_definition]
  }
}
