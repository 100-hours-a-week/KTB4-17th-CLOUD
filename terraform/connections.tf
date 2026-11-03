# Cross-owner SG edges live here to avoid service/network/ALB dependency cycles.
locals {
  additional_ecs_services            = { ws = { database_access = var.ws_database_access }, ai = { database_access = var.ai_database_access } }
  database_client_security_group_ids = { be = module.be.security_group_id, ws = module.ws.security_group_id, ai = module.ai.security_group_id }
  v1_database_ingress_rules          = var.v1_database_network == null ? {} : merge({ be-mysql = { service = "be", database = "mysql" } }, local.additional_ecs_database_rules)
  v1_database_security_group_ids     = var.v1_database_network == null ? {} : { v1 = { mysql = var.v1_database_network.mysql_security_group_id, postgres = var.v1_database_network.postgres_security_group_id } }
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id = module.network.alb_security_group_id

  referenced_security_group_id = module.be.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = local.app_port
  to_port                      = local.app_port

  tags = {
    Name = "${local.name_prefix}-alb-to-app-egress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id = module.be.security_group_id

  referenced_security_group_id = module.network.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = local.app_port
  to_port                      = local.app_port

  tags = {
    Name = "${local.name_prefix}-app-from-alb-ingress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "mysql_from_app" {
  security_group_id = module.network.mysql_security_group_id

  referenced_security_group_id = module.be.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = local.mysql_port
  to_port                      = local.mysql_port

  tags = {
    Name = "${local.name_prefix}-mysql-from-app-ingress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_app" {
  security_group_id = module.network.postgres_security_group_id

  referenced_security_group_id = module.be.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = local.postgres_port
  to_port                      = local.postgres_port

  tags = {
    Name = "${local.name_prefix}-postgres-from-app-ingress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ws_from_alb" {
  security_group_id            = module.ws.security_group_id
  referenced_security_group_id = module.network.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.ws_port
  to_port                      = var.ws_port

  tags = {
    Name        = "${local.name_prefix}-ws-from-alb"
    environment = var.environment
  }
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ws" {
  security_group_id            = module.network.alb_security_group_id
  referenced_security_group_id = module.ws.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.ws_port
  to_port                      = var.ws_port

  tags = {
    Name        = "${local.name_prefix}-alb-to-ws"
    environment = var.environment
  }
}

resource "aws_vpc_security_group_ingress_rule" "ai_from_be" {
  security_group_id            = module.ai.security_group_id
  referenced_security_group_id = module.be.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.ai_port
  to_port                      = var.ai_port

  tags = {
    Name        = "${local.name_prefix}-ai-from-be"
    environment = var.environment
  }
}

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
      security_group_id = module.network.mysql_security_group_id
      port              = local.mysql_port
    }
    postgres = {
      security_group_id = module.network.postgres_security_group_id
      port              = local.postgres_port
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "additional_ecs_database" {
  for_each = local.additional_ecs_database_rules

  security_group_id            = local.ecs_database_settings[each.value.database].security_group_id
  referenced_security_group_id = local.database_client_security_group_ids[each.value.service]
  ip_protocol                  = "tcp"
  from_port                    = local.ecs_database_settings[each.value.database].port
  to_port                      = local.ecs_database_settings[each.value.database].port

  tags = {
    Name        = "${local.name_prefix}-${each.value.database}-from-${each.value.service}"
    environment = var.environment
  }
}

resource "aws_vpc_security_group_ingress_rule" "ai_from_ws" {
  security_group_id            = module.ai.security_group_id
  referenced_security_group_id = module.ws.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.ai_port
  to_port                      = var.ai_port
  description                  = "AI practice calls from ECS websocket workers"

  tags = {
    Name        = "${local.name_prefix}-ai-from-ws"
    environment = var.environment
  }
}

resource "aws_vpc_security_group_ingress_rule" "v1_database_from_ecs" {
  for_each = local.v1_database_ingress_rules

  security_group_id            = local.v1_database_security_group_ids["v1"][each.value.database]
  referenced_security_group_id = local.database_client_security_group_ids[each.value.service]
  ip_protocol                  = "tcp"
  from_port                    = local.ecs_database_settings[each.value.database].port
  to_port                      = local.ecs_database_settings[each.value.database].port

  tags = {
    Name        = "${local.name_prefix}-v1-${each.value.database}-from-${each.value.service}"
    environment = var.environment
  }

  # Cross-VPC security group references require an active peering connection.
  depends_on = [module.network.v1_database_peering_connection_id]
}
