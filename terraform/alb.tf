resource "aws_alb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = "ipv4"

  security_groups = [aws_security_group.alb.id]

  subnets = [
    aws_subnet.public["2a"].id,
    aws_subnet.public["2c"].id
  ]

  enable_deletion_protection = true

  tags = {
    Name = "${local.name_prefix}-alb"
  }

  depends_on = [
    aws_internet_gateway.main,
    aws_route_table.public,
    aws_route_table_association.public
  ]
}

resource "aws_lb_listener_rule" "ws" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ws.arn
  }

  condition {
    path_pattern {
      values = ["/ws", "/ws/*"]
    }
  }

  tags = {
    Name        = "${local.name_prefix}-ws-listener-rule"
    environment = "prod"
  }
}
