/**
 * Monitoring security group
 *
 * Grafana 공개 HTTPS와 기존 관리자 접근을 제공하며, Loki는 Lambda SG에서만 수신한다.
 */
resource "aws_security_group" "monitoring" {
  name        = "star23-v2-monitoring"
  description = "V2 production monitoring"
  vpc_id      = var.vpc_id
  tags        = { Name = "star23-v2-monitoring", environment = "prod" }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.monitoring.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.monitoring.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each          = var.ssh_cidrs
  security_group_id = aws_security_group.monitoring.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "grafana_admin" {
  for_each          = var.grafana_admin_cidrs
  security_group_id = aws_security_group.monitoring.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 3000
  to_port           = 3000
}

resource "aws_vpc_security_group_egress_rule" "outbound" {
  security_group_id = aws_security_group.monitoring.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

/**
 * Loki ingress
 *
 * Lambda 전달 SG에서 들어오는 TCP 3100만 허용한다.
 */
resource "aws_vpc_security_group_ingress_rule" "loki_from_forwarder" {
  security_group_id            = aws_security_group.monitoring.id
  referenced_security_group_id = var.lambda_forwarder_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 3100
  to_port                      = 3100
  description                  = "CloudWatch Lambda V2 log forwarder"
  tags = {
    Name        = "star23-prod-cloudwatch-loki"
    environment = "prod"
    project     = "star23"
    managed_by  = "terraform"
  }
}
