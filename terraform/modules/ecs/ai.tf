# AI Task Definition과 Service. 리비전 배포는 CD가 담당한다.

resource "aws_ecs_task_definition" "ai" {
  family                   = "${var.name_prefix}-ai"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.service_execution["ai"].arn
  task_role_arn            = aws_iam_role.service_task["ai"].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.ai_cpu_architecture
  }

  container_definitions = jsonencode([{
    name      = "ai"
    image     = "${var.ai_repository_url}:${var.ai_image_tag}"
    essential = true

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service["ai"].name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    portMappings = [{
      name          = "ai-http"
      containerPort = var.ai_port
      protocol      = "tcp"
      appProtocol   = "http"
    }]

    environment = [
      for name, value in var.ai_environment : {
        name  = name
        value = value
      }
    ]
    secrets = [
      for name, value_from in var.ai_secrets : {
        name      = name
        valueFrom = value_from
      }
    ]

    # ALB를 사용하지 않는 AI도 준비 상태를 검사한다. FastAPI 이미지에 python3가 필요하다.
    healthCheck = {
      command = [
        "CMD", "python3", "-c",
        "import urllib.request; r = urllib.request.urlopen(${jsonencode("http://127.0.0.1:${var.ai_port}${var.ai_health_check_path}")}, timeout=2); raise SystemExit(0 if r.status == 200 else 1)"
      ]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 120
    }
  }])

  tags = {
    Name        = "${var.name_prefix}-ai-task"
    environment = "prod"
  }

  depends_on = [
    aws_iam_role_policy_attachment.service_execution,
    aws_iam_role_policy.service_execution_secrets,
    aws_iam_role_policy.service_execution_secret_kms,
    aws_secretsmanager_secret_version.be
  ]
}

resource "aws_ecs_service" "ai" {
  name                  = "${var.name_prefix}-ai-service"
  cluster               = aws_ecs_cluster.main.id
  task_definition       = aws_ecs_task_definition.ai.arn
  launch_type           = "FARGATE"
  platform_version      = "LATEST"
  desired_count         = var.ai_desired_count
  propagate_tags        = "SERVICE"
  wait_for_steady_state = true

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  availability_zone_rebalancing      = "ENABLED"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets = var.application_subnet_ids

    security_groups  = [var.additional_ecs_security_group_ids["ai"]]
    assign_public_ip = false
  }

  # BE의 Service Connect 클라이언트가 http://ai:<ai_port>로 호출한다.
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.ecs.arn

    service {
      port_name      = "ai-http"
      discovery_name = "ai"

      client_alias {
        dns_name = "ai"
        port     = var.ai_port
      }

      timeout {
        per_request_timeout_seconds = var.ai_request_timeout_seconds
        idle_timeout_seconds        = var.ai_request_timeout_seconds == 0 ? 0 : max(300, var.ai_request_timeout_seconds)
      }
    }
  }

  tags = {
    Name        = "${var.name_prefix}-ai-service"
    environment = "prod"
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}
