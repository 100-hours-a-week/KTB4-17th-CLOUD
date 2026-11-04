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
  subnet_id         = module.subnet.public_ids[each.key]
  connectivity_type = "public"
  availability_mode = "zonal"

  tags = {
    Name = "${var.name_prefix}-nat-${each.key}"
  }

  depends_on = [module.vpc.internet_gateway_id]
}
