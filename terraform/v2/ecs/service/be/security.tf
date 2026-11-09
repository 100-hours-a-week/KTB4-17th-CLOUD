/**
 * BE security group
 */
resource "aws_security_group" "app" {
  vpc_id = var.vpc_id

  name        = "${var.name_prefix}-app-sg"
  description = "APP-SG"
}

resource "aws_vpc_security_group_egress_rule" "app_outbound_rule" {
  security_group_id = aws_security_group.app.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  tags = {
    Name = "${var.name_prefix}-app-outbound-egress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id = aws_security_group.app.id

  referenced_security_group_id = var.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = local.app_port
  to_port                      = local.app_port

  tags = {
    Name = "${var.name_prefix}-app-from-alb-ingress"
  }
}
