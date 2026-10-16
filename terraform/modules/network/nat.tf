locals {
  nat_zones = {
    (var.nat_gateway_zone) = var.zones[var.nat_gateway_zone]
  }
}

resource "aws_eip" "nat" {
  for_each = local.nat_zones
  domain   = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-eip-${each.key}"
  }
}

resource "aws_nat_gateway" "main" {
  for_each          = local.nat_zones
  allocation_id     = aws_eip.nat[each.key].id
  subnet_id         = aws_subnet.public[each.key].id
  connectivity_type = "public"
  availability_mode = "zonal"

  tags = {
    Name = "${var.name_prefix}-nat-${each.key}"
  }

  depends_on = [aws_internet_gateway.main]
}
