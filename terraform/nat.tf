resource "aws_eip" "nat" {
  for_each = local.zones
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip-${each.key}"
  }
}

resource "aws_nat_gateway" "main" {
  for_each          = local.zones
  allocation_id     = aws_eip.nat[each.key].id
  subnet_id         = aws_subnet.public[each.key].id
  connectivity_type = "public"
  availability_mode = "zonal"

  tags = {
    Name = "${local.name_prefix}-nat-${each.key}"
  }

  depends_on = [aws_internet_gateway.main]
}

moved {
  from = aws_eip.nat
  to   = aws_eip.nat["2a"]
}
