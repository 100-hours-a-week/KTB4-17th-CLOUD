output "id" { value = aws_ecs_cluster.main.id }
output "name" { value = aws_ecs_cluster.main.name }
output "namespace_arn" { value = aws_service_discovery_http_namespace.ecs.arn }
