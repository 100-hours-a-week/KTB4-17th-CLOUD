output "service_name" { value = try(aws_ecs_service.ws[0].name, null) }
output "security_group_id" {
  value      = aws_security_group.service.id
  depends_on = [aws_vpc_security_group_egress_rule.outbound]
}
