output "vpc_id" { value = module.vpc.id }
output "public_subnet_ids" {
  value      = [for key in sort(keys(var.zones)) : module.subnet.public_ids[key]]
  depends_on = [module.routetable.public_ready]
}
output "application_subnet_ids" {
  value      = [for key in sort(keys(var.zones)) : module.subnet.application_ids[key]]
  depends_on = [module.routetable.application_ready, aws_vpc_peering_connection.v1_database, aws_route.application_to_v1_database, aws_route.v1_database_to_application]
}
output "data_subnet_ids" {
  value      = [for key in sort(keys(var.zones)) : module.subnet.data_ids[key]]
  depends_on = [module.routetable.data_ready]
}
output "v1_database_peering_connection_id" {
  value      = try(aws_vpc_peering_connection.v1_database["v1"].id, null)
  depends_on = [aws_route.application_to_v1_database, aws_route.v1_database_to_application]
}
