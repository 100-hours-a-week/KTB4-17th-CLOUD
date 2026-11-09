output "instance_id" { value = aws_instance.monitoring.id }
output "private_ip" { value = aws_instance.monitoring.private_ip }
output "public_ip" { value = aws_instance.monitoring.public_ip }
output "subnet_id" { value = aws_instance.monitoring.subnet_id }
output "security_group_id" { value = aws_security_group.monitoring.id }
