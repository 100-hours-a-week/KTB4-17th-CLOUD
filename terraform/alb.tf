resource "aws_alb" "main" {
  name = "${local.name_prefix}-alb"
  internal = false
  load_balancer_type = "application"
  ip_address_type = "ipv4"

  security_groups = [aws_security_group.alb.id]

  subnets = [
    aws_subnet.public["2a"].id,
    aws_subnet.public["2c"].id
  ]

  enable_deletion_protection = true

  tags = {
    Name = "${local.name_prefix}-alb"
  }

  depends_on = [
    aws_internet_gateway.main,
    aws_route_table.public,
    aws_route_table_association.public
  ]
}