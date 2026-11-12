/** Existing EKS private subnets
 * V2 VPC의 기존 서브넷 두 개를 유지하며 VPC와 NAT의 소유권은 V2에 둔다.
 */
locals {
  private_subnets = {
    "2a" = {
      az         = "ap-northeast-2a"
      cidr_block = "10.1.66.0/23"
      name       = "star-EKS-private-2a"
    }
    "2c" = {
      az         = "ap-northeast-2c"
      cidr_block = "10.1.68.0/23"
      name       = "star-EKS-private-2c"
    }
  }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id                                         = var.vpc_id
  availability_zone                              = each.value.az
  cidr_block                                     = each.value.cidr_block
  map_public_ip_on_launch                        = false
  assign_ipv6_address_on_creation                = false
  enable_dns64                                   = false
  private_dns_hostname_type_on_launch            = "ip-name"
  enable_resource_name_dns_a_record_on_launch    = false
  enable_resource_name_dns_aaaa_record_on_launch = false
  tags                                           = { Name = each.value.name }

  lifecycle {
    prevent_destroy = true
  }
}

/** Shared NAT route
 * 기존 main 테이블의 암묵적 서브넷 연결은 유지하고 NAT 경로 하나만 관리한다.
 */
data "aws_route_table" "main" {
  vpc_id = var.vpc_id

  filter {
    name   = "association.main"
    values = ["true"]
  }
}

resource "aws_route" "private_nat" {
  route_table_id         = data.aws_route_table.main.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.nat_gateway_id
}
