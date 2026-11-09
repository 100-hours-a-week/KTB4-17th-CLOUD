/**
 * Connection settings
 *
 * 서비스·네트워크·ALB 사이의 순환 의존성을 피하도록 교차 SG 규칙을 여기에서 연결한다.
 */
locals {
  additional_ecs_services            = { ws = { database_access = var.ws_database_access }, ai = { database_access = var.ai_database_access } }
  database_client_security_group_ids = { be = module.be.security_group_id, ws = module.ws.security_group_id, ai = module.ai.security_group_id }
  v1_database_ingress_rules          = var.v1_database_network == null ? {} : merge({ be-mysql = { service = "be", database = "mysql" } }, local.additional_ecs_database_rules)
  v1_database_security_group_ids     = var.v1_database_network == null ? {} : { v1 = { mysql = var.v1_database_network.mysql_security_group_id, postgres = var.v1_database_network.postgres_security_group_id } }
}

/**
 * ALB to backend
 *
 * ALB 송신과 백엔드 수신 규칙을 한 쌍으로 연결한다.
 */
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id = module.alb.alb_security_group_id

  referenced_security_group_id = module.be.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = module.be.port
  to_port                      = module.be.port

  tags = {
    Name = "${local.name_prefix}-alb-to-app-egress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id = module.be.security_group_id

  referenced_security_group_id = module.alb.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = module.be.port
  to_port                      = module.be.port

  tags = {
    Name = "${local.name_prefix}-app-from-alb-ingress"
  }
}

/**
 * Backend database access
 *
 * 백엔드 SG에서 MySQL·PostgreSQL로 들어오는 연결을 허용한다.
 */
resource "aws_vpc_security_group_ingress_rule" "mysql_from_app" {
  security_group_id = module.database.mysql_security_group_id

  referenced_security_group_id = module.be.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = local.mysql_port
  to_port                      = local.mysql_port

  tags = {
    Name = "${local.name_prefix}-mysql-from-app-ingress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_app" {
  security_group_id = module.database.postgres_security_group_id

  referenced_security_group_id = module.be.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = local.postgres_port
  to_port                      = local.postgres_port

  tags = {
    Name = "${local.name_prefix}-postgres-from-app-ingress"
  }
}

/**
 * ALB to websocket
 *
 * ALB 송신과 웹소켓 서비스 수신 규칙을 한 쌍으로 연결한다.
 */
resource "aws_vpc_security_group_ingress_rule" "ws_from_alb" {
  security_group_id            = module.ws.security_group_id
  referenced_security_group_id = module.alb.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = module.ws.port
  to_port                      = module.ws.port

  tags = {
    Name        = "${local.name_prefix}-ws-from-alb"
    environment = local.environment
  }
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ws" {
  security_group_id            = module.alb.alb_security_group_id
  referenced_security_group_id = module.ws.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = module.ws.port
  to_port                      = module.ws.port

  tags = {
    Name        = "${local.name_prefix}-alb-to-ws"
    environment = local.environment
  }
}

/**
 * Backend to AI
 */
resource "aws_vpc_security_group_ingress_rule" "ai_from_be" {
  security_group_id            = module.ai.security_group_id
  referenced_security_group_id = module.be.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = module.ai.port
  to_port                      = module.ai.port

  tags = {
    Name        = "${local.name_prefix}-ai-from-be"
    environment = local.environment
  }
}

/**
 * Additional database access
 *
 * WS·AI의 DB 접근 목록을 DB별 수신 규칙으로 펼친다.
 */
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
      security_group_id = module.database.mysql_security_group_id
      port              = local.mysql_port
    }
    postgres = {
      security_group_id = module.database.postgres_security_group_id
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
    environment = local.environment
  }
}

/**
 * Websocket to AI
 */
resource "aws_vpc_security_group_ingress_rule" "ai_from_ws" {
  security_group_id            = module.ai.security_group_id
  referenced_security_group_id = module.ws.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = module.ai.port
  to_port                      = module.ai.port
  description                  = "AI practice calls from ECS websocket workers"

  tags = {
    Name        = "${local.name_prefix}-ai-from-ws"
    environment = local.environment
  }
}

/**
 * Legacy database access
 *
 * V1 DB 네트워크가 연결된 경우에만 ECS 서비스의 접근을 허용한다.
 */
resource "aws_vpc_security_group_ingress_rule" "v1_database_from_ecs" {
  for_each = local.v1_database_ingress_rules

  security_group_id            = local.v1_database_security_group_ids["v1"][each.value.database]
  referenced_security_group_id = local.database_client_security_group_ids[each.value.service]
  ip_protocol                  = "tcp"
  from_port                    = local.ecs_database_settings[each.value.database].port
  to_port                      = local.ecs_database_settings[each.value.database].port

  tags = {
    Name        = "${local.name_prefix}-v1-${each.value.database}-from-${each.value.service}"
    environment = local.environment
  }

  # Cross-VPC security group references require an active peering connection.
  depends_on = [module.network.v1_database_peering_connection_id]
}
