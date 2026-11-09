/**
 * AI logs
 */
resource "aws_cloudwatch_log_group" "service" {
  count             = true ? 1 : 0
  name              = "/ecs/${var.name_prefix}/${var.environment}/ai"
  retention_in_days = 30
  tags              = { Name = "${var.name_prefix}-${var.environment}-ai-logs", environment = var.environment }
}
