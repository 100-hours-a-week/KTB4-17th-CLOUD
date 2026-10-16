data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "service" {
  for_each = toset(concat(["be", "ai"], var.ws_enabled ? ["ws"] : []))

  name              = "/ecs/${var.name_prefix}/prod/${each.key}"
  retention_in_days = 30

  tags = {
    Name        = "${var.name_prefix}-prod-${each.key}-logs"
    environment = "prod"
  }
}
