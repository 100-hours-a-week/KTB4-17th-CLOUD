resource "aws_route_table" "public" {
  vpc_id = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = var.internet_gateway_id
}

resource "aws_route_table_association" "public" {
  for_each = var.zones

  subnet_id      = var.public_subnet_ids[each.key]
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "application" {
  for_each = var.zones

  vpc_id = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-app-private-rt-${each.key}"
  }
}

resource "aws_route" "app_nat" {
  for_each = var.zones

  route_table_id         = aws_route_table.application[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.nat_gateway_id
}

resource "aws_route_table_association" "application" {
  for_each = var.zones

  subnet_id      = var.application_subnet_ids[each.key]
  route_table_id = aws_route_table.application[each.key].id
}

resource "aws_route_table" "data" {
  for_each = var.zones

  vpc_id = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-data-private-rt-${each.key}"
  }
}

resource "aws_route_table_association" "data" {
  for_each = var.zones

  subnet_id      = var.data_subnet_ids[each.key]
  route_table_id = aws_route_table.data[each.key].id
}
