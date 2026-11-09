terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

removed {
  from = aws_ecs_task_definition.ai
  lifecycle { destroy = false }
}

moved {
  from = aws_ecs_service.ai
  to   = aws_ecs_service.ai[0]
}

/**
 * AI service
 *
 * 외부 태스크 리비전을 연결하며, 실행 수와 후속 배포는 CI/CD가 관리한다.
 */
resource "aws_ecs_service" "ai" {
  count                 = var.services_enabled ? 1 : 0
  name                  = "${var.name_prefix}-ai-service"
  cluster               = var.cluster_id
  task_definition       = var.task_definition_arn
  launch_type           = "FARGATE"
  platform_version      = "LATEST"
  desired_count         = 0
  propagate_tags        = "SERVICE"
  wait_for_steady_state = true

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  availability_zone_rebalancing      = "ENABLED"

  deployment_circuit_breaker {
    enable   = false
    rollback = false
  }

  network_configuration {
    subnets = var.subnet_ids

    security_groups  = [aws_security_group.service.id]
    assign_public_ip = false
  }

  # BE의 Service Connect 클라이언트가 http://ai:<ai_port>로 호출한다.
  service_connect_configuration {
    enabled   = true
    namespace = var.namespace_arn

    service {
      port_name      = "ai-http"
      discovery_name = "ai"

      client_alias {
        dns_name = "ai"
        port     = local.ai_port
      }

      timeout {
        per_request_timeout_seconds = local.ai_request_timeout_seconds
        idle_timeout_seconds        = local.ai_request_timeout_seconds == 0 ? 0 : max(300, local.ai_request_timeout_seconds)
      }
    }
  }

  tags = {
    Name        = "${var.name_prefix}-ai-service"
    environment = var.environment
  }

  depends_on = [aws_vpc_security_group_egress_rule.outbound, aws_vpc_security_group_ingress_rule.ai_from_be, aws_vpc_security_group_ingress_rule.ai_from_ws, var.traffic_rule_ids]

  lifecycle {
    ignore_changes  = [task_definition, desired_count]
    prevent_destroy = true
    precondition {
      condition     = var.task_definition_arn != null
      error_message = "Supply an externally registered task definition ARN before creating service shells."
    }
  }
}
