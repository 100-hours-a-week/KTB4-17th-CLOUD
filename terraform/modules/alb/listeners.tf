resource "aws_lb_listener_rule" "ws" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = var.ws_enabled ? aws_lb_target_group.ws.arn : aws_lb_target_group.api.arn
  }

  condition {
    path_pattern {
      values = ["/ws", "/ws/*"]
    }
  }

  tags = {
    Name        = "${var.name_prefix}-ws-listener-rule"
    environment = "prod"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_alb.main.id
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  tags = {
    Name = "${var.name_prefix}-https-listener"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_alb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = 443
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = {
    Name = "${var.name_prefix}-http-listener"
  }

  depends_on = [aws_lb_listener.https]
}
