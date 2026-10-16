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

  v1_database_ingress_rules = var.v1_database_network == null ? {} : merge(
    { be-mysql = { service = "be", database = "mysql" } },
    local.additional_ecs_database_rules,
  )

  v1_database_security_group_ids = {
    for key, peer in local.v1_database_peers : key => {
      mysql    = peer.mysql_security_group_id
      postgres = peer.postgres_security_group_id
    }
  }

  database_client_security_group_ids = merge(
    { be = aws_security_group.app.id },
    { for name, group in aws_security_group.ecs_service : name => group.id },
  )
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
    Name        = "${var.name_prefix}-v2-to-v1-database"
    environment = "prod"
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

# Keep existing v1 routes to other 10.1.0.0/16 VPCs: only these ECS subnets return here.
resource "aws_route" "v1_database_to_application" {
  for_each = local.v1_database_return_routes

  route_table_id            = each.value.route_table_id
  destination_cidr_block    = each.value.app_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.v1_database["v1"].id
}

# These rules belong to the actual v1 database SGs, not the unused SGs in the new VPC.
resource "aws_vpc_security_group_ingress_rule" "v1_database_from_ecs" {
  for_each = local.v1_database_ingress_rules

  security_group_id            = local.v1_database_security_group_ids["v1"][each.value.database]
  referenced_security_group_id = local.database_client_security_group_ids[each.value.service]
  ip_protocol                  = "tcp"
  from_port                    = local.ecs_database_settings[each.value.database].port
  to_port                      = local.ecs_database_settings[each.value.database].port

  tags = {
    Name        = "${var.name_prefix}-v1-${each.value.database}-from-${each.value.service}"
    environment = "prod"
  }

  # Cross-VPC security group references require an active peering connection.
  depends_on = [aws_vpc_peering_connection.v1_database]
}
