resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-ecs-cluster"

  tags = {
    Name = "${local.name_prefix}-ecs-cluster"
  }
}

resource "aws_service_discovery_http_namespace" "ecs" {
  name        = "${local.name_prefix}-prod"
  description = "Internal ECS service connections for star23 production"

  tags = {
    Name        = "${local.name_prefix}-prod"
    environment = "prod"
  }
}

data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ECS가 ECR 이미지를 가져오고, 지정한 시크릿을 컨테이너에 주입할 때 사용한다.
resource "aws_iam_role" "ecs_execution" {
  name               = "${local.name_prefix}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    Name        = "${local.name_prefix}-ecs-execution-role"
    environment = "prod"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 애플리케이션 자체가 AWS API를 호출할 때 사용한다.
# 앱에 필요한 S3 등의 접근 정책은 이 역할에 추가한다.
resource "aws_iam_role" "ecs_task" {
  name               = "${local.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    Name        = "${local.name_prefix}-ecs-task-role"
    environment = "prod"
  }
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  count = length(var.be_secrets) > 0 ? 1 : 0

  name = "${local.name_prefix}-ecs-execution-secrets"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for value_from in values(var.be_secrets) : {
        Effect = "Allow"
        Action = startswith(value_from, "arn:aws:secretsmanager:") ? ["secretsmanager:GetSecretValue"] : ["ssm:GetParameters"]
        # Secrets Manager의 JSON key/version 선택자는 IAM 리소스 ARN에서 제외한다.
        Resource = startswith(value_from, "arn:aws:secretsmanager:") ? join(":", slice(split(":", value_from), 0, 7)) : value_from
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_execution_secret_kms" {
  count = length(var.be_secret_kms_key_arns) > 0 ? 1 : 0

  name = "${local.name_prefix}-ecs-execution-secret-kms"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = var.be_secret_kms_key_arns
    }]
  })
}

# BE의 기존 리소스 주소를 유지하고, WS/AI는 서비스별 역할을 추가한다.
locals {
  additional_ecs_services = {
    ws = {
      secrets         = var.ws_secrets
      kms_key_arns    = var.ws_secret_kms_key_arns
      database_access = var.ws_database_access
    }
    ai = {
      secrets         = var.ai_secrets
      kms_key_arns    = var.ai_secret_kms_key_arns
      database_access = var.ai_database_access
    }
  }
}

resource "aws_iam_role" "service_execution" {
  for_each = local.additional_ecs_services

  name               = "${local.name_prefix}-${each.key}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    Name        = "${local.name_prefix}-${each.key}-ecs-execution-role"
    environment = "prod"
  }
}

resource "aws_iam_role_policy_attachment" "service_execution" {
  for_each = local.additional_ecs_services

  role       = aws_iam_role.service_execution[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 앱별 AWS API 접근 권한은 해당 Task Role에 추가한다.
resource "aws_iam_role" "service_task" {
  for_each = local.additional_ecs_services

  name               = "${local.name_prefix}-${each.key}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    Name        = "${local.name_prefix}-${each.key}-ecs-task-role"
    environment = "prod"
  }
}

resource "aws_iam_role_policy" "service_execution_secrets" {
  for_each = {
    for name, settings in local.additional_ecs_services : name => settings
    if length(settings.secrets) > 0
  }

  name = "${local.name_prefix}-${each.key}-ecs-execution-secrets"
  role = aws_iam_role.service_execution[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for value_from in values(each.value.secrets) : {
        Effect   = "Allow"
        Action   = startswith(value_from, "arn:aws:secretsmanager:") ? ["secretsmanager:GetSecretValue"] : ["ssm:GetParameters"]
        Resource = startswith(value_from, "arn:aws:secretsmanager:") ? join(":", slice(split(":", value_from), 0, 7)) : value_from
      }
    ]
  })
}

resource "aws_iam_role_policy" "service_execution_secret_kms" {
  for_each = {
    for name, settings in local.additional_ecs_services : name => settings
    if length(settings.kms_key_arns) > 0
  }

  name = "${local.name_prefix}-${each.key}-ecs-execution-secret-kms"
  role = aws_iam_role.service_execution[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = each.value.kms_key_arns
    }]
  })
}

resource "aws_ecs_task_definition" "be" {
  family                   = "${local.name_prefix}-be"
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
      image     = "${aws_ecr_repository.be.repository_url}:${var.be_image_tag}"
      essential = true

      portMappings = [{
        name          = "http"
        containerPort = local.app_port
        protocol      = "tcp"
        appProtocol   = "http"
      }]

      environment = [
        for name, value in var.be_environment : {
          name  = name
          value = value
        }
      ]

      secrets = [
        for name, value_from in var.be_secrets : {
          name      = name
          valueFrom = value_from
        }
      ]
    }
  ])

  tags = {
    Name        = "${local.name_prefix}-be-task"
    environment = "prod"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_execution,
    aws_iam_role_policy.ecs_execution_secrets,
    aws_iam_role_policy.ecs_execution_secret_kms
  ]
}

resource "aws_ecs_task_definition" "ws" {
  family                   = "${local.name_prefix}-ws"
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
      for name, value_from in var.ws_secrets : {
        name      = name
        valueFrom = value_from
      }
    ]
  }])

  tags = {
    Name        = "${local.name_prefix}-ws-task"
    environment = "prod"
  }

  depends_on = [
    aws_iam_role_policy_attachment.service_execution,
    aws_iam_role_policy.service_execution_secrets,
    aws_iam_role_policy.service_execution_secret_kms
  ]
}

resource "aws_ecs_task_definition" "ai" {
  family                   = "${local.name_prefix}-ai"
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
    image     = "${aws_ecr_repository.ai.repository_url}:${var.ai_image_tag}"
    essential = true

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
    Name        = "${local.name_prefix}-ai-task"
    environment = "prod"
  }

  depends_on = [
    aws_iam_role_policy_attachment.service_execution,
    aws_iam_role_policy.service_execution_secrets,
    aws_iam_role_policy.service_execution_secret_kms
  ]
}

resource "aws_ecs_service" "be" {
  name                  = "${local.name_prefix}-be-service"
  cluster               = aws_ecs_cluster.main.id
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
    subnets = [for key in sort(keys(local.zones)) : aws_subnet.application[key].id]

    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "be"
    container_port   = local.app_port
  }

  # BE 태스크는 Service Connect를 통해 ai라는 이름으로 AI 엔드포인트를 조회한다.
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.ecs.arn
  }

  tags = {
    Name        = "${local.name_prefix}-be-service"
    environment = "prod"
  }

  # 생성 후 리비전 업데이트는 CI/CD가 담당한다. Terraform이 배포된 버전을 되돌리지 않도록 한다.
  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [
    aws_lb_listener.https,
    aws_lb_listener.http,
    aws_route.app_nat,
    aws_route_table_association.application,
    aws_vpc_security_group_egress_rule.alb_to_app,
    aws_vpc_security_group_ingress_rule.app_from_alb,
    aws_vpc_security_group_egress_rule.app_outbound_rule,
    # AI 엔드포인트가 먼저 등록되어야 새 BE 태스크가 이를 조회할 수 있다.
    aws_ecs_service.ai
  ]
}

resource "aws_ecs_service" "ws" {
  name                  = "${local.name_prefix}-ws-service"
  cluster               = aws_ecs_cluster.main.id
  task_definition       = aws_ecs_task_definition.ws.arn
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
    subnets = [for key in sort(keys(local.zones)) : aws_subnet.application[key].id]

    security_groups  = [aws_security_group.ecs_service["ws"].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ws.arn
    container_name   = "ws"
    container_port   = var.ws_port
  }

  tags = {
    Name        = "${local.name_prefix}-ws-service"
    environment = "prod"
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [
    aws_lb_listener_rule.ws,
    aws_route.app_nat,
    aws_route_table_association.application,
    aws_vpc_security_group_egress_rule.alb_to_ws,
    aws_vpc_security_group_ingress_rule.ws_from_alb,
    aws_vpc_security_group_egress_rule.ecs_service_outbound,
    aws_vpc_security_group_ingress_rule.additional_ecs_database
  ]
}

resource "aws_ecs_service" "ai" {
  name                  = "${local.name_prefix}-ai-service"
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
    subnets = [for key in sort(keys(local.zones)) : aws_subnet.application[key].id]

    security_groups  = [aws_security_group.ecs_service["ai"].id]
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
    Name        = "${local.name_prefix}-ai-service"
    environment = "prod"
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [
    aws_route.app_nat,
    aws_route_table_association.application,
    aws_vpc_security_group_ingress_rule.ai_from_be,
    aws_vpc_security_group_egress_rule.ecs_service_outbound,
    aws_vpc_security_group_ingress_rule.additional_ecs_database
  ]
}
