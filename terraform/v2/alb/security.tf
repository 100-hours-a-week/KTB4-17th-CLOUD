/**
 * ALB security group
 *
 * 보안 그룹과 HTTP·HTTPS 수신 및 서비스 송신 규칙을 함께 구성한다.
 */
resource "aws_security_group" "alb" {
  vpc_id = var.vpc_id

  name        = "${var.name_prefix}-alb-sg"
  description = "ALB-SG"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443

  tags = {
    Name = "${var.name_prefix}-alb-https-ingress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id = aws_security_group.alb.id

  referenced_security_group_id = var.be_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port

  tags = {
    Name = "${var.name_prefix}-alb-to-app-egress"
  }
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ws" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = var.ws_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.ws_port
  to_port                      = var.ws_port

  tags = {
    Name        = "${var.name_prefix}-alb-to-ws"
    environment = var.environment
  }
}
