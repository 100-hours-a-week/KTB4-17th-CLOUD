output "vpc_id" {
  description = "VPC used by the application."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnets, ordered by zone key and ready for the load balancer."
  value       = [for key in sort(keys(var.zones)) : aws_subnet.public[key].id]

  depends_on = [
    aws_internet_gateway.main,
    aws_route_table.public,
    aws_route.public_internet,
    aws_route_table_association.public,
  ]
}

output "application_subnet_ids" {
  description = "Private application subnets, ordered by zone key and ready for ECS outbound traffic."
  value       = [for key in sort(keys(var.zones)) : aws_subnet.application[key].id]

  depends_on = [
    aws_route.app_nat,
    aws_route_table_association.application,
    aws_vpc_peering_connection.v1_database,
    aws_route.application_to_v1_database,
    aws_route.v1_database_to_application,
  ]
}

output "alb_security_group_id" {
  description = "Shared ALB security group; cross-owner egress is composed at root."
  value       = aws_security_group.alb.id

  depends_on = [
    aws_vpc_security_group_ingress_rule.alb_http,
    aws_vpc_security_group_ingress_rule.alb_https,
  ]
}

output "v1_database_peering_connection_id" {
  description = "Peering connection to the existing v1 database VPC, when configured."
  value       = try(aws_vpc_peering_connection.v1_database["v1"].id, null)

  depends_on = [
    aws_route.application_to_v1_database,
    aws_route.v1_database_to_application,
  ]
}

output "data_subnet_ids" {
  description = "Private data subnets, ordered by zone key and ready for the DB subnet group."
  value       = [for key in sort(keys(var.zones)) : aws_subnet.data[key].id]

  depends_on = [aws_route_table_association.data]
}

output "mysql_security_group_id" {
  description = "Shared MySQL security group; service ingress is composed at root."
  value       = aws_security_group.mysql.id
}

output "postgres_security_group_id" {
  description = "Shared PostgreSQL security group; service ingress is composed at root."
  value       = aws_security_group.postgres.id
}
