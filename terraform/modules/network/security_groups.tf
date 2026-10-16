locals {
  additional_ecs_services = {
    ws = { database_access = var.ws_database_access }
    ai = { database_access = var.ai_database_access }
  }
}

resource "aws_security_group" "alb" {
  vpc_id = aws_vpc.main.id

  name        = "${var.name_prefix}-alb-sg"
  description = "ALB-SG"
}

resource "aws_security_group" "app" {
  vpc_id = aws_vpc.main.id

  name        = "${var.name_prefix}-app-sg"
  description = "APP-SG"
}

resource "aws_security_group" "mysql" {
  vpc_id = aws_vpc.main.id

  name        = "${var.name_prefix}-mysql-sg"
  description = "MYSQL-SG"
}

resource "aws_security_group" "postgres" {
  vpc_id = aws_vpc.main.id

  name        = "${var.name_prefix}-postgres-sg"
  description = "POSTGRES-SG"
}

resource "aws_security_group" "ecs_service" {
  for_each = local.additional_ecs_services

  name        = "${var.name_prefix}-${each.key}-sg"
  description = "Security group for the ${each.key} ECS service"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.name_prefix}-${each.key}-sg"
    environment = "prod"
  }
}
