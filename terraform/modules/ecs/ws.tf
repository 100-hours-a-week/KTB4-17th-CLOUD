# WS Task Definition과 Service. 리비전 배포는 CD가 담당한다.

moved {
  from = aws_ecs_task_definition.ws
  to   = aws_ecs_task_definition.ws[0]
}

moved {
  from = aws_ecs_service.ws
  to   = aws_ecs_service.ws[0]
}

resource "aws_ecs_task_definition" "ws" {
  count = var.ws_enabled ? 1 : 0

  family                   = "${var.name_prefix}-ws"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.service_execution["ws"].arn
  task_role_arn            = aws_iam_role.service_task["ws"].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.ws_cpu_architecture
  }

  container_definitions = jsonencode([{
    name      = "ws"
    image     = var.ws_image_uri
    essential = true

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service["ws"].name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    portMappings = [{
      name          = "ws"
      containerPort = var.ws_port
      protocol      = "tcp"
    }]

    environment = [
      for name, value in var.ws_environment : {
        name  = name
        value = value
      }
    ]
    secrets = [
      for name, value_from in local.ws_secret_references : {
        name      = name
        valueFrom = value_from
      }
    ]
  }])

  tags = {
    Name        = "${var.name_prefix}-ws-task"
    environment = "prod"
  }

  depends_on = [
    aws_iam_role_policy_attachment.service_execution,
    aws_iam_role_policy.service_execution_secrets,
    aws_iam_role_policy.service_execution_secret_kms,
    aws_iam_role_policy.ws_s3,
    aws_secretsmanager_secret_version.be,
  ]
}

resource "aws_ecs_service" "ws" {
  count = var.ws_enabled ? 1 : 0

  name                  = "${var.name_prefix}-ws-service"
  cluster               = aws_ecs_cluster.main.id
  task_definition       = aws_ecs_task_definition.ws[0].arn
  launch_type           = "FARGATE"
  platform_version      = "LATEST"
  desired_count         = var.ws_desired_count
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
    subnets = var.application_subnet_ids

    security_groups  = [var.additional_ecs_security_group_ids["ws"]]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.ws_target_group_arn
    container_name   = "ws"
    container_port   = var.ws_port
  }

  dynamic "service_connect_configuration" {
    for_each = var.ws_use_backend_config ? [true] : []

    content {
      enabled   = true
      namespace = aws_service_discovery_http_namespace.ecs.arn
    }
  }

  tags = {
    Name        = "${var.name_prefix}-ws-service"
    environment = "prod"
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}
