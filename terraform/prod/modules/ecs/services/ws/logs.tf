resource "aws_cloudwatch_log_group" "service" {
  count             = var.ws_enabled ? 1 : 0
  name              = "/ecs/${var.name_prefix}/${var.environment}/ws"
  retention_in_days = 30
  tags              = { Name = "${var.name_prefix}-${var.environment}-ws-logs", environment = var.environment }
}
