resource "aws_alb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = "ipv4"
  idle_timeout       = 120

  depends_on = [aws_vpc_security_group_ingress_rule.alb_http, aws_vpc_security_group_ingress_rule.alb_https]

  security_groups = [aws_security_group.alb.id]

  subnets = var.public_subnet_ids

  enable_deletion_protection = true

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}
