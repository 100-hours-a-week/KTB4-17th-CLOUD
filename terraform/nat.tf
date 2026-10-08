resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip-2a"
  }
}

resource "aws_nat_gateway" "main" {
  for_each          = local.zones
  allocation_id     = aws_eip.nat.id
  subnet_id         = aws_subnet.public[each.key].id
  connectivity_type = "public"
  availability_mode = "zonal"

  tags = {
    Name = "${local.name_prefix}-nat-${each.key}"
  }

  depends_on = [aws_internet_gateway.main]
}