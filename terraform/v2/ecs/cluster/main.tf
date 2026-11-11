terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# ECS 클러스터와 서비스 간 통신 네임스페이스.

/**
 * ECS cluster
 */
resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-ecs-cluster"

  tags = {
    Name = "${var.name_prefix}-ecs-cluster"
  }
}

/**
 * ECS namespace
 */
resource "aws_service_discovery_http_namespace" "ecs" {
  name        = "${var.name_prefix}-${var.environment}"
  description = "Internal ECS service connections for ${var.name_prefix} ${var.environment == "prod" ? "production" : var.environment}"

  tags = {
    Name        = "${var.name_prefix}-${var.environment}"
    environment = var.environment
  }
}
