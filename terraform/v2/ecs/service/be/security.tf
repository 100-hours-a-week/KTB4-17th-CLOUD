/**
 * BE security group
 */
resource "aws_security_group" "app" {
  vpc_id = var.vpc_id

  name        = "${var.name_prefix}-app-sg"
  description = "APP-SG"
}

resource "aws_vpc_security_group_egress_rule" "app_outbound_rule" {
  security_group_id = aws_security_group.app.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  tags = {
    Name = "${var.name_prefix}-app-outbound-egress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id = aws_security_group.app.id

  referenced_security_group_id = var.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = local.app_port
  to_port                      = local.app_port

  tags = {
    Name = "${var.name_prefix}-app-from-alb-ingress"
  }
}

/**
 * Monitoring scrape
 *
 * V2 모니터링 SG에서 오는 Prometheus 수집 요청만 허용한다.
 */
resource "aws_vpc_security_group_ingress_rule" "metrics_from_monitoring" {
  count                        = var.monitoring_security_group_id == null ? 0 : 1
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = var.monitoring_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = local.app_port
  to_port                      = local.app_port
  description                  = "Prometheus scrape from V2 monitoring"
  tags                         = { Name = "${var.name_prefix}-app-from-monitoring", environment = var.environment }
}

/** Existing migration access
 * 외부 migration SG에서 허용된 기존 TCP 3306 규칙을 그대로 관리한다.
 */
data "aws_security_group" "migration" {
  vpc_id = var.vpc_id
  name   = "star23-prod-migration-rabbitmq"
}

resource "aws_vpc_security_group_ingress_rule" "app_from_migration" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = data.aws_security_group.migration.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  description                  = "Temporary MySQL migration access"
}
