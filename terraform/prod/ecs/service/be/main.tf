terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

removed {
  from = aws_ecs_task_definition.be
  lifecycle { destroy = false }
}

moved {
  from = aws_ecs_service.be
  to   = aws_ecs_service.be[0]
}

/**
 * BE service
 *
 * 외부 태스크 리비전을 연결하며, 실행 수와 후속 배포는 CI/CD가 관리한다.
 */
resource "aws_ecs_service" "be" {
  count                 = var.services_enabled ? 1 : 0
  name                  = "${var.name_prefix}-be-service"
  cluster               = var.cluster_id
  task_definition       = var.task_definition_arn
  launch_type           = "FARGATE"
  platform_version      = "LATEST"
  desired_count         = 0
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
    container_port   = local.app_port
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

  # CI/CD owns task revisions and scaling, including the first application start.
  depends_on = [var.ai_service_name, aws_vpc_security_group_egress_rule.app_outbound_rule, var.traffic_rule_ids]

  lifecycle {
    ignore_changes  = [task_definition, desired_count]
    prevent_destroy = true
    precondition {
      condition     = var.task_definition_arn != null
      error_message = "Supply an externally registered task definition ARN before creating service shells."
    }
  }
}
