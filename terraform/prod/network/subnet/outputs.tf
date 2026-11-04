output "public_ids" { value = { for key, subnet in aws_subnet.public : key => subnet.id } }
output "application_ids" { value = { for key, subnet in aws_subnet.application : key => subnet.id } }
output "data_ids" { value = { for key, subnet in aws_subnet.data : key => subnet.id } }
