output "network" {
  description = "Managed V1 network IDs; shared consumers require network deletion protection."
  value = {
    vpc_id              = module.network.vpc_id
    subnet_ids          = module.network.subnet_ids
    route_table_ids     = module.network.route_table_ids
    internet_gateway_id = module.network.internet_gateway_id
  }
}
