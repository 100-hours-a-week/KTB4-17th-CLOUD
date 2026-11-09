/**
 * WS security group
 */
resource "aws_security_group" "service" {
  name        = "${var.name_prefix}-ws-sg"
  description = "Security group for the ws ECS service"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-ws-sg", environment = var.environment }
}
resource "aws_vpc_security_group_egress_rule" "outbound" {
  security_group_id = aws_security_group.service.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  tags              = { Name = "${var.name_prefix}-ws-outbound-egress", environment = var.environment }
}

resource "aws_vpc_security_group_ingress_rule" "ws_from_alb" {
  security_group_id            = aws_security_group.service.id
  referenced_security_group_id = var.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = local.ws_port
  to_port                      = local.ws_port

  tags = {
    Name        = "${var.name_prefix}-ws-from-alb"
    environment = var.environment
  }
}
