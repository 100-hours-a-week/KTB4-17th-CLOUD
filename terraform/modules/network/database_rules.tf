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
      port              = var.mysql_port
    }
    postgres = {
      security_group_id = aws_security_group.postgres.id
      port              = var.postgres_port
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
    Name        = "${var.name_prefix}-${each.value.database}-from-${each.value.service}"
    environment = "prod"
  }
}
