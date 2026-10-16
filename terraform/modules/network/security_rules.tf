resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443

  tags = {
    Name = "${var.name_prefix}-alb-https-ingress"
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
  from_port                    = var.app_port
  to_port                      = var.app_port

  tags = {
    Name = "${var.name_prefix}-alb-to-app-egress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id = aws_security_group.app.id

  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port

  tags = {
    Name = "${var.name_prefix}-app-from-alb-ingress"
  }
}

resource "aws_vpc_security_group_egress_rule" "app_outbound_rule" {
  security_group_id = aws_security_group.app.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  tags = {
    Name = "${var.name_prefix}-app-outbound-egress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "mysql_from_app" {
  security_group_id = aws_security_group.mysql.id

  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.mysql_port
  to_port                      = var.mysql_port

  tags = {
    Name = "${var.name_prefix}-mysql-from-app-ingress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_app" {
  security_group_id = aws_security_group.postgres.id

  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.postgres_port
  to_port                      = var.postgres_port

  tags = {
    Name = "${var.name_prefix}-postgres-from-app-ingress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ws_from_alb" {
  security_group_id            = aws_security_group.ecs_service["ws"].id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.ws_port
  to_port                      = var.ws_port

  tags = {
    Name        = "${var.name_prefix}-ws-from-alb"
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
    Name        = "${var.name_prefix}-alb-to-ws"
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
    Name        = "${var.name_prefix}-ai-from-be"
    environment = "prod"
  }
}

resource "aws_vpc_security_group_egress_rule" "ecs_service_outbound" {
  for_each = local.additional_ecs_services

  security_group_id = aws_security_group.ecs_service[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = {
    Name        = "${var.name_prefix}-${each.key}-outbound-egress"
    environment = "prod"
  }
}
