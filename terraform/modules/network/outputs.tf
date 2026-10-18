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
  description = "ALB security group with listener ingress and service egress rules."
  value       = aws_security_group.alb.id

  depends_on = [
    aws_vpc_security_group_ingress_rule.alb_https,
    aws_vpc_security_group_ingress_rule.alb_http,
    aws_vpc_security_group_egress_rule.alb_to_app,
    aws_vpc_security_group_egress_rule.alb_to_ws,
  ]
}

output "be_security_group_id" {
  description = "Backend security group with inbound, outbound, and database rules."
  value       = aws_security_group.app.id

  depends_on = [
    aws_vpc_security_group_egress_rule.alb_to_app,
    aws_vpc_security_group_ingress_rule.app_from_alb,
    aws_vpc_security_group_egress_rule.app_outbound_rule,
    aws_vpc_security_group_ingress_rule.mysql_from_app,
    aws_vpc_security_group_ingress_rule.postgres_from_app,
    aws_vpc_security_group_ingress_rule.ai_from_be,
    aws_vpc_security_group_ingress_rule.v1_database_from_ecs,
  ]
}

output "additional_ecs_security_group_ids" {
  description = "WebSocket and AI security groups with service and database rules."
  value       = { for name, group in aws_security_group.ecs_service : name => group.id }

  depends_on = [
    aws_vpc_security_group_ingress_rule.ws_from_alb,
    aws_vpc_security_group_egress_rule.alb_to_ws,
    aws_vpc_security_group_ingress_rule.ai_from_be,
    aws_vpc_security_group_egress_rule.ecs_service_outbound,
    aws_vpc_security_group_ingress_rule.additional_ecs_database,
    aws_vpc_security_group_ingress_rule.v1_database_from_ecs,
  ]
}

output "v1_database_peering_connection_id" {
  description = "Peering connection to the existing v1 database VPC, when configured."
  value       = try(aws_vpc_peering_connection.v1_database["v1"].id, null)

  depends_on = [
    aws_route.application_to_v1_database,
    aws_route.v1_database_to_application,
    aws_vpc_security_group_ingress_rule.v1_database_from_ecs,
  ]
}

output "data_subnet_ids" {
  description = "Private data subnets, ordered by zone key and ready for the DB subnet group."
  value       = [for key in sort(keys(var.zones)) : aws_subnet.data[key].id]

  depends_on = [aws_route_table_association.data]
}

output "mysql_security_group_id" {
  description = "MySQL security group with ingress rules from the ECS services."
  value       = aws_security_group.mysql.id

  depends_on = [
    aws_vpc_security_group_ingress_rule.mysql_from_app,
    aws_vpc_security_group_ingress_rule.additional_ecs_database,
  ]
}

output "postgres_security_group_id" {
  description = "PostgreSQL security group with ingress rules from the ECS services."
  value       = aws_security_group.postgres.id

  depends_on = [
    aws_vpc_security_group_ingress_rule.postgres_from_app,
    aws_vpc_security_group_ingress_rule.additional_ecs_database,
  ]
}
