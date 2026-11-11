output "subnet_ids" { value = module.subnet.ids }
output "vpc_id" { value = module.vpc.id }
output "internet_gateway_id" { value = module.vpc.internet_gateway_id }
output "route_table_ids" { value = module.routetable.ids }
