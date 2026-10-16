resource "aws_alb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = "ipv4"

  security_groups = [var.alb_security_group_id]

  subnets = var.public_subnet_ids

  enable_deletion_protection = true

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}
