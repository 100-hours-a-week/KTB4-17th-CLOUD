terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "vpc_id" { type = string }
variable "default_route_table_id" { type = string }
variable "internet_gateway_id" { type = string }
variable "subnet_ids" { type = map(string) }

/**
 * Shared V1 routing tables
 *
 * inline route는 지정하지 않는다. prod 소유 경로 2개와 외부 peering 경로를 보존한다.
 */
resource "aws_route_table" "public" {
  vpc_id = var.vpc_id

  tags = {
    Name    = "star23-public-route-table"
    Service = "star23"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_default_route_table" "main" {
  default_route_table_id = var.default_route_table_id
  tags                   = {}

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = var.internet_gateway_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route_table_association" "public" {
  for_each = var.subnet_ids

  subnet_id      = each.value
  route_table_id = aws_route_table.public.id

  lifecycle {
    prevent_destroy = true
  }
}

output "ids" {
  value = {
    public = aws_route_table.public.id
    main   = aws_default_route_table.main.id
  }
}
