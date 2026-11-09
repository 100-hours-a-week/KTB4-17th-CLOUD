
resource "aws_cloudwatch_log_group" "service" {

  name              = "/ecs/${var.name_prefix}/${var.environment}/be"
  retention_in_days = 30

  tags = {
    Name        = "${var.name_prefix}-${var.environment}-be-logs"
    environment = var.environment
  }
}
