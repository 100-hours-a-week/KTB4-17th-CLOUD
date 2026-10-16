# Preserve existing state addresses when moving resources into modules.
# Keep this migration history for existing environments.

moved {
  from = aws_eip.nat
  to   = aws_eip.nat["2a"]
}

moved {
  from = aws_vpc.main
  to   = module.network.aws_vpc.main
}

moved {
  from = aws_internet_gateway.main
  to   = module.network.aws_internet_gateway.main
}

moved {
  from = aws_subnet.public
  to   = module.network.aws_subnet.public
}

moved {
  from = aws_subnet.application
  to   = module.network.aws_subnet.application
}

moved {
  from = aws_subnet.data
  to   = module.network.aws_subnet.data
}

moved {
  from = aws_route_table.public
  to   = module.network.aws_route_table.public
}

moved {
  from = aws_route.public_internet
  to   = module.network.aws_route.public_internet
}

moved {
  from = aws_route_table_association.public
  to   = module.network.aws_route_table_association.public
}

moved {
  from = aws_route_table.application
  to   = module.network.aws_route_table.application
}

moved {
  from = aws_route.app_nat
  to   = module.network.aws_route.app_nat
}

moved {
  from = aws_route_table_association.application
  to   = module.network.aws_route_table_association.application
}

moved {
  from = aws_route_table.data
  to   = module.network.aws_route_table.data
}

moved {
  from = aws_route_table_association.data
  to   = module.network.aws_route_table_association.data
}

moved {
  from = aws_eip.nat["2a"]
  to   = module.network.aws_eip.nat["2a"]
}

moved {
  from = aws_eip.nat["2c"]
  to   = module.network.aws_eip.nat["2c"]
}

moved {
  from = aws_nat_gateway.main
  to   = module.network.aws_nat_gateway.main
}

moved {
  from = aws_security_group.alb
  to   = module.network.aws_security_group.alb
}

moved {
  from = aws_security_group.app
  to   = module.network.aws_security_group.app
}

moved {
  from = aws_security_group.mysql
  to   = module.network.aws_security_group.mysql
}

moved {
  from = aws_security_group.postgres
  to   = module.network.aws_security_group.postgres
}

moved {
  from = aws_vpc_security_group_ingress_rule.alb_https
  to   = module.network.aws_vpc_security_group_ingress_rule.alb_https
}

moved {
  from = aws_vpc_security_group_ingress_rule.alb_http
  to   = module.network.aws_vpc_security_group_ingress_rule.alb_http
}

moved {
  from = aws_vpc_security_group_egress_rule.alb_to_app
  to   = module.network.aws_vpc_security_group_egress_rule.alb_to_app
}

moved {
  from = aws_vpc_security_group_ingress_rule.app_from_alb
  to   = module.network.aws_vpc_security_group_ingress_rule.app_from_alb
}

moved {
  from = aws_vpc_security_group_egress_rule.app_outbound_rule
  to   = module.network.aws_vpc_security_group_egress_rule.app_outbound_rule
}

moved {
  from = aws_vpc_security_group_ingress_rule.mysql_from_app
  to   = module.network.aws_vpc_security_group_ingress_rule.mysql_from_app
}

moved {
  from = aws_vpc_security_group_ingress_rule.postgres_from_app
  to   = module.network.aws_vpc_security_group_ingress_rule.postgres_from_app
}

moved {
  from = aws_security_group.ecs_service
  to   = module.network.aws_security_group.ecs_service
}

moved {
  from = aws_vpc_security_group_ingress_rule.ws_from_alb
  to   = module.network.aws_vpc_security_group_ingress_rule.ws_from_alb
}

moved {
  from = aws_vpc_security_group_egress_rule.alb_to_ws
  to   = module.network.aws_vpc_security_group_egress_rule.alb_to_ws
}

moved {
  from = aws_vpc_security_group_ingress_rule.ai_from_be
  to   = module.network.aws_vpc_security_group_ingress_rule.ai_from_be
}

moved {
  from = aws_vpc_security_group_egress_rule.ecs_service_outbound
  to   = module.network.aws_vpc_security_group_egress_rule.ecs_service_outbound
}

moved {
  from = aws_vpc_security_group_ingress_rule.additional_ecs_database
  to   = module.network.aws_vpc_security_group_ingress_rule.additional_ecs_database
}
