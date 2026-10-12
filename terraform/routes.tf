resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  for_each = local.zones

  subnet_id = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "application" {
  for_each = local.zones

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-app-private-rt-${each.key}"
  }
}

resource "aws_route" "app_nat" {
  for_each = local.zones

  route_table_id = aws_route_table.application[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_nat_gateway.main[each.key].id
}

resource "aws_route_table_association" "application" {
  for_each = local.zones

  subnet_id = aws_subnet.application[each.key].id
  route_table_id = aws_route_table.application[each.key].id
}

resource "aws_route_table" "data" {
  for_each = local.zones

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-data-private-rt-${each.key}"
  }
}

resource "aws_route_table_association" "data" {
  for_each = local.zones

  subnet_id = aws_subnet.data[each.key].id
  route_table_id = aws_route_table.data[each.key].id
}