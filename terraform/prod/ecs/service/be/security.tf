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
