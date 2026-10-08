resource "aws_security_group" "alb" {
  vpc_id = aws_vpc.main.id

  name = "${local.name_prefix}-alb-sg"
  description = "ALB-SG"
}

resource "aws_security_group" "app" {
  vpc_id = aws_vpc.main.id

  name = "${local.name_prefix}-app-sg"
  description = "APP-SG"
}

resource "aws_security_group" "mysql" {
  vpc_id = aws_vpc.main.id

  name = "${local.name_prefix}-mysql-sg"
  description = "MYSQL-SG"
}

resource "aws_security_group" "postgres" {
  vpc_id = aws_vpc.main.id

  name = "${local.name_prefix}-postgres-sg"
  description = "POSTGRES-SG"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id

  cidr_ipv4 = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port = 443
  to_port = 443

  tags = {
    Name = "${local.name_prefix}-alb-https-ingress"
  }
}
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4 = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port = 80
  to_port = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id = aws_security_group.alb.id

  referenced_security_group_id = aws_security_group.app.id
  ip_protocol = "tcp"
  from_port = local.app_port
  to_port = local.app_port

  tags = {
    Name = "${local.name_prefix}-alb-to-app-egress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id = aws_security_group.app.id

  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol = "tcp"
  from_port = local.app_port
  to_port = local.app_port

  tags = {
    Name = "${local.name_prefix}-app-from-alb-ingress"
  }
}

resource "aws_vpc_security_group_egress_rule" "app_outbound_rule" {
  security_group_id = aws_security_group.app.id

  cidr_ipv4 = "0.0.0.0/0"
  ip_protocol = "-1"

  tags = {
    Name = "${local.name_prefix}-app-outbound-egress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "mysql_from_app" {
  security_group_id = aws_security_group.mysql.id

  referenced_security_group_id = aws_security_group.app.id
  ip_protocol       = "tcp"
  from_port = local.mysql_port
  to_port = local.mysql_port

  tags = {
    Name = "${local.name_prefix}-mysql-from-app-ingress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_app" {
  security_group_id = aws_security_group.postgres.id

  referenced_security_group_id = aws_security_group.app.id
  ip_protocol       = "tcp"
  from_port = local.postgres_port
  to_port = local.postgres_port

  tags = {
    Name = "${local.name_prefix}-postgres-from-app-ingress"
  }
}