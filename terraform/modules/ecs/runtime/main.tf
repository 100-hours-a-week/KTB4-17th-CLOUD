locals {
  additional_ecs_services = var.enabled ? { (var.service_name) = {
    secrets      = var.secrets
    kms_key_arns = var.kms_key_arns
  } } : {}
}
resource "aws_security_group" "service" {
  name        = "${var.name_prefix}-${var.service_name}-sg"
  description = "Security group for the ${var.service_name} ECS service"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-${var.service_name}-sg", environment = var.environment }
}
resource "aws_vpc_security_group_egress_rule" "outbound" {
  security_group_id = aws_security_group.service.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  tags              = { Name = "${var.name_prefix}-${var.service_name}-outbound-egress", environment = var.environment }
}
resource "aws_cloudwatch_log_group" "service" {
  count             = var.enabled ? 1 : 0
  name              = "/ecs/${var.name_prefix}/${var.environment}/${var.service_name}"
  retention_in_days = 30
  tags              = { Name = "${var.name_prefix}-${var.environment}-${var.service_name}-logs", environment = var.environment }
}
