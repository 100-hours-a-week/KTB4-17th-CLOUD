resource "aws_lb_target_group" "api" {
  vpc_id = aws_vpc.main.id

  name        = "${local.name_prefix}-api-tg"
  port        = local.app_port
  protocol    = "HTTP"
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = local.health_check_path
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${local.name_prefix}-api-tg"
  }
}