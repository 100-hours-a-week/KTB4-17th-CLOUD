resource "aws_subnet" "public" {
  for_each = local.zones

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.value.az
  cidr_block              = each.value.public_cidr
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-public-${each.key}"
  }
}

resource "aws_subnet" "application" {
  for_each = local.zones

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.value.az
  cidr_block              = each.value.app_cidr
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-app-${each.key}"
  }
}

resource "aws_subnet" "data" {
  for_each = local.zones

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.value.az
  cidr_block              = each.value.data_cidr
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-data-${each.key}"
  }
}