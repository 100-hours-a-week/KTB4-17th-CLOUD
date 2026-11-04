output "application_ids" { value = { for key, rt in aws_route_table.application : key => rt.id } }
output "public_ready" {
  value      = true
  depends_on = [aws_route.public_internet, aws_route_table_association.public]
}
output "application_ready" {
  value      = true
  depends_on = [aws_route.app_nat, aws_route_table_association.application]
}
output "data_ready" {
  value      = true
  depends_on = [aws_route_table_association.data]
}