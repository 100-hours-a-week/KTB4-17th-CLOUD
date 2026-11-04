variable "vpc_id" { type = string }
data "aws_route_tables" "existing" { vpc_id = var.vpc_id }
output "ids" { value = data.aws_route_tables.existing.ids }
