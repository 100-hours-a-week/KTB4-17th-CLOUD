resource "aws_vpc_security_group_ingress_rule" "ai_from_ws" {
  security_group_id            = aws_security_group.ecs_service["ai"].id
  referenced_security_group_id = aws_security_group.ecs_service["ws"].id
  ip_protocol                  = "tcp"
  from_port                    = var.ai_port
  to_port                      = var.ai_port
  description                  = "AI practice calls from ECS websocket workers"

  tags = {
    Name        = "${var.name_prefix}-ai-from-ws"
    environment = "prod"
  }
}
