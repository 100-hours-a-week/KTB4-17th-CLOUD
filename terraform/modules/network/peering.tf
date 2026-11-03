locals {
  v1_database_peers = var.v1_database_network == null ? {} : {
    v1 = var.v1_database_network
  }

  v1_database_return_routes = {
    for route in flatten([
      for peer in values(local.v1_database_peers) : [
        for route_table_id in peer.route_table_ids : [
          for zone, settings in var.zones : {
            key            = "${route_table_id}-${zone}"
            route_table_id = route_table_id
            app_cidr       = settings.app_cidr
          }
        ]
      ]
    ]) : route.key => route
  }
}

data "aws_vpc" "v1_database" {
  for_each = local.v1_database_peers

  id = each.value.vpc_id
}

resource "aws_vpc_peering_connection" "v1_database" {
  for_each = local.v1_database_peers

  vpc_id      = aws_vpc.main.id
  peer_vpc_id = data.aws_vpc.v1_database[each.key].id
  auto_accept = true

  tags = {
    Name        = "${var.name_prefix}-${var.vpc_version}-to-v1-database"
    environment = var.environment
  }

  lifecycle {
    precondition {
      condition     = data.aws_vpc.v1_database[each.key].owner_id == aws_vpc.main.owner_id
      error_message = "Automatic acceptance requires the existing v1 VPC to belong to the same AWS account."
    }
  }
}

resource "aws_route" "application_to_v1_database" {
  for_each = var.v1_database_network == null ? {} : var.zones

  route_table_id            = aws_route_table.application[each.key].id
  destination_cidr_block    = data.aws_vpc.v1_database["v1"].cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.v1_database["v1"].id
}

# Preserve other VPC return routes; only these application /24 subnets return here.
resource "aws_route" "v1_database_to_application" {
  for_each = local.v1_database_return_routes

  route_table_id            = each.value.route_table_id
  destination_cidr_block    = each.value.app_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.v1_database["v1"].id
}
