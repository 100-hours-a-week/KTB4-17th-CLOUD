resource "aws_security_group" "alb" {
  vpc_id = aws_vpc.main.id

  name        = "${local.name_prefix}-alb-sg"
  description = "ALB-SG"
}

resource "aws_security_group" "app" {
  vpc_id = aws_vpc.main.id

  name        = "${local.name_prefix}-app-sg"
  description = "APP-SG"
}

resource "aws_security_group" "mysql" {
  vpc_id = aws_vpc.main.id

  name        = "${local.name_prefix}-mysql-sg"
  description = "MYSQL-SG"
}

resource "aws_security_group" "postgres" {
  vpc_id = aws_vpc.main.id

  name        = "${local.name_prefix}-postgres-sg"
  description = "POSTGRES-SG"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443

  tags = {
    Name = "${local.name_prefix}-alb-https-ingress"
  }
}
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id = aws_security_group.alb.id

  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = local.app_port
  to_port                      = local.app_port

  tags = {
    Name = "${local.name_prefix}-alb-to-app-egress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id = aws_security_group.app.id

  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = local.app_port
  to_port                      = local.app_port

  tags = {
    Name = "${local.name_prefix}-app-from-alb-ingress"
  }
}

resource "aws_vpc_security_group_egress_rule" "app_outbound_rule" {
  security_group_id = aws_security_group.app.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  tags = {
    Name = "${local.name_prefix}-app-outbound-egress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "mysql_from_app" {
  security_group_id = aws_security_group.mysql.id

  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = local.mysql_port
  to_port                      = local.mysql_port

  tags = {
    Name = "${local.name_prefix}-mysql-from-app-ingress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_app" {
  security_group_id = aws_security_group.postgres.id

  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = local.postgres_port
  to_port                      = local.postgres_port

  tags = {
    Name = "${local.name_prefix}-postgres-from-app-ingress"
  }
}

resource "aws_security_group" "ecs_service" {
  for_each = local.additional_ecs_services

  name        = "${local.name_prefix}-${each.key}-sg"
  description = "Security group for the ${each.key} ECS service"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${local.name_prefix}-${each.key}-sg"
    environment = "prod"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ws_from_alb" {
  security_group_id            = aws_security_group.ecs_service["ws"].id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.ws_port
  to_port                      = var.ws_port

  tags = {
    Name        = "${local.name_prefix}-ws-from-alb"
    environment = "prod"
  }
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ws" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.ecs_service["ws"].id
  ip_protocol                  = "tcp"
  from_port                    = var.ws_port
  to_port                      = var.ws_port

  tags = {
    Name        = "${local.name_prefix}-alb-to-ws"
    environment = "prod"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ai_from_be" {
  security_group_id            = aws_security_group.ecs_service["ai"].id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.ai_port
  to_port                      = var.ai_port

  tags = {
    Name        = "${local.name_prefix}-ai-from-be"
    environment = "prod"
  }
}

# Private subnet에서 NAT를 통해 이미지와 외부 API에 접근한다.
resource "aws_vpc_security_group_egress_rule" "ecs_service_outbound" {
  for_each = local.additional_ecs_services

  security_group_id = aws_security_group.ecs_service[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = {
    Name        = "${local.name_prefix}-${each.key}-outbound-egress"
    environment = "prod"
  }
}

# 필요한 서비스에만 기존 MySQL/PostgreSQL 보안 그룹의 접근을 허용한다.
locals {
  additional_ecs_database_rules = {
    for rule in flatten([
      for service_name, settings in local.additional_ecs_services : [
        for database in settings.database_access : {
          key      = "${service_name}-${database}"
          service  = service_name
          database = database
        }
      ]
    ]) : rule.key => rule
  }

  ecs_database_settings = {
    mysql = {
      security_group_id = aws_security_group.mysql.id
      port              = local.mysql_port
    }
    postgres = {
      security_group_id = aws_security_group.postgres.id
      port              = local.postgres_port
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "additional_ecs_database" {
  for_each = local.additional_ecs_database_rules

  security_group_id            = local.ecs_database_settings[each.value.database].security_group_id
  referenced_security_group_id = aws_security_group.ecs_service[each.value.service].id
  ip_protocol                  = "tcp"
  from_port                    = local.ecs_database_settings[each.value.database].port
  to_port                      = local.ecs_database_settings[each.value.database].port

  tags = {
    Name        = "${local.name_prefix}-${each.value.database}-from-${each.value.service}"
    environment = "prod"
  }
}
