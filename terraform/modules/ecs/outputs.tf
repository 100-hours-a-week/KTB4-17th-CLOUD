output "service_names" {
  description = "ECS service names used by application CI/CD"
  value = merge(
    {
      be = aws_ecs_service.be.name
      ai = aws_ecs_service.ai.name
    },
    var.ws_enabled ? { ws = aws_ecs_service.ws[0].name } : {},
  )
}

output "ai_internal_url" {
  description = "AI URL available to the backend Service Connect client"
  value       = "http://ai:${var.ai_port}"
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}
