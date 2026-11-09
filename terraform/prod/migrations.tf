/**
 * Security rule ownership migration
 *
 * 기존 규칙 ID를 유지하며 리소스 소유 모듈로 주소만 옮긴다.
 */
moved {
  from = aws_vpc_security_group_egress_rule.alb_to_app
  to   = module.alb.aws_vpc_security_group_egress_rule.alb_to_app
}

moved {
  from = aws_vpc_security_group_egress_rule.alb_to_ws
  to   = module.alb.aws_vpc_security_group_egress_rule.alb_to_ws
}

moved {
  from = aws_vpc_security_group_ingress_rule.app_from_alb
  to   = module.be.aws_vpc_security_group_ingress_rule.app_from_alb
}

moved {
  from = aws_vpc_security_group_ingress_rule.ws_from_alb
  to   = module.ws.aws_vpc_security_group_ingress_rule.ws_from_alb
}

moved {
  from = aws_vpc_security_group_ingress_rule.ai_from_be
  to   = module.ai.aws_vpc_security_group_ingress_rule.ai_from_be
}

moved {
  from = aws_vpc_security_group_ingress_rule.ai_from_ws
  to   = module.ai.aws_vpc_security_group_ingress_rule.ai_from_ws
}

moved {
  from = aws_vpc_security_group_ingress_rule.mysql_from_app
  to   = module.database.aws_vpc_security_group_ingress_rule.mysql_from_app
}

moved {
  from = aws_vpc_security_group_ingress_rule.postgres_from_app
  to   = module.database.aws_vpc_security_group_ingress_rule.postgres_from_app
}

moved {
  from = aws_vpc_security_group_ingress_rule.additional_ecs_database["ai-postgres"]
  to   = module.database.aws_vpc_security_group_ingress_rule.postgres_from_ai
}

moved {
  from = aws_vpc_security_group_ingress_rule.additional_ecs_database["ws-mysql"]
  to   = module.database.aws_vpc_security_group_ingress_rule.mysql_from_ws
}

moved {
  from = aws_vpc_security_group_ingress_rule.v1_database_from_ecs["be-mysql"]
  to   = module.database.aws_vpc_security_group_ingress_rule.v1_mysql_from_be[0]
}

moved {
  from = aws_vpc_security_group_ingress_rule.v1_database_from_ecs["ws-mysql"]
  to   = module.database.aws_vpc_security_group_ingress_rule.v1_mysql_from_ws[0]
}

moved {
  from = aws_vpc_security_group_ingress_rule.v1_database_from_ecs["ai-postgres"]
  to   = module.database.aws_vpc_security_group_ingress_rule.v1_postgres_from_ai[0]
}
