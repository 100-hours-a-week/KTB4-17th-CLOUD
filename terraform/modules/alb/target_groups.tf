resource "aws_lb_target_group" "api" {
  vpc_id = var.vpc_id

  name        = "${var.name_prefix}-api-tg"
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = var.health_check_path
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.name_prefix}-api-tg"
  }
}

resource "aws_lb_target_group" "ws" {
  name        = "${var.name_prefix}-ws-tg"
  vpc_id      = var.vpc_id
  port        = var.ws_port
  protocol    = "HTTP"
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = var.ws_health_check_path
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.name_prefix}-ws-tg"
    environment = "prod"
  }
}
