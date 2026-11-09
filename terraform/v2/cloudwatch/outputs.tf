output "monitoring" {
  description = "Terraform-owned V2 monitoring instance and automatically assigned addresses."
  value = {
    instance_id       = module.monitoring.instance_id
    private_ip        = module.monitoring.private_ip
    public_ip         = module.monitoring.public_ip
    security_group_id = module.monitoring.security_group_id
  }
}

output "function_name" {
  value = module.cloudwatch_loki.function_name
}

output "function_arn" {
  value = module.cloudwatch_loki.function_arn
}

output "subscription_filter_names" {
  value = module.cloudwatch_loki.subscription_filter_names
}

output "failed_events_queue_url" {
  value = module.cloudwatch_loki.failed_events_queue_url
}

output "grafana_logql" {
  value = "{environment=\"prod\", source=\"cloudwatch\"}"
}

output "deployment_infrastructure" {
  value = module.cloudwatch_loki.deployment_infrastructure
}
