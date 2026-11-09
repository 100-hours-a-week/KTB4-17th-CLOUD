/**
 * Lambda security group
 *
 * V2 Loki TCP 3100으로의 송신만 허용하며 수신 포트는 열지 않는다.
 */
resource "aws_security_group" "forwarder_v2" {
  name        = "${var.name}-v2"
  description = "CloudWatch log forwarder: outbound only to V2 Loki"
  vpc_id      = var.vpc_id
  tags        = local.tags
}

resource "aws_vpc_security_group_egress_rule" "to_loki_v2" {
  security_group_id            = aws_security_group.forwarder_v2.id
  referenced_security_group_id = var.loki_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 3100
  to_port                      = 3100
  description                  = "Lambda-promtail to V2 Loki HTTP only"
  tags                         = local.tags
}
