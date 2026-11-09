/**
 * ALB security group
 *
 * 보안 그룹과 HTTP·HTTPS 인바운드 규칙을 함께 구성한다.
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
