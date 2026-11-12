output "vpc_id" { value = module.vpc.id }
output "public_subnet_ids" {
  value      = [for key in sort(keys(var.zones)) : module.subnet.public_ids[key]]
  depends_on = [module.routetable.public_ready]
}
output "application_subnet_ids" {
  value      = [for key in sort(keys(var.zones)) : module.subnet.application_ids[key]]
  depends_on = [module.routetable.application_ready]
}
output "data_subnet_ids" {
  value      = [for key in sort(keys(var.zones)) : module.subnet.data_ids[key]]
  depends_on = [module.routetable.data_ready]
}

output "nat_gateway_id" {
  value = aws_nat_gateway.main[var.nat_gateway_zone].id
}
