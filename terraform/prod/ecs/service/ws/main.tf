terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

removed {
  from = aws_ecs_task_definition.ws
  lifecycle { destroy = false }
}

resource "aws_ecs_service" "ws" {
  count = var.ws_enabled && var.services_enabled ? 1 : 0

  name                  = "${var.name_prefix}-ws-service"
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

    security_groups  = [aws_security_group.service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.ws_target_group_arn
    container_name   = "ws"
    container_port   = local.ws_port
  }

  dynamic "service_connect_configuration" {
    for_each = var.ws_use_backend_config ? [true] : []

    content {
      enabled   = true
      namespace = var.namespace_arn
    }
  }

  tags = {
    Name        = "${var.name_prefix}-ws-service"
    environment = var.environment
  }

  depends_on = [aws_vpc_security_group_egress_rule.outbound, var.traffic_rule_ids]

  lifecycle {
    ignore_changes  = [task_definition, desired_count]
    prevent_destroy = true
    precondition {
      condition     = var.task_definition_arn != null
      error_message = "Supply an externally registered task definition ARN before creating service shells."
    }
  }
}
