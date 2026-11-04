output "function_name" {
  value = aws_lambda_function.forwarder.function_name
}

output "function_arn" {
  value = aws_lambda_function.forwarder.arn
}

output "security_group_id" {
  value = aws_security_group.forwarder.id
}

output "loki_ingress_rule_id" {
  value = aws_vpc_security_group_ingress_rule.loki_from_forwarder.id
}

output "lambda_log_group_name" {
  value = aws_cloudwatch_log_group.forwarder.name
}

output "failed_events_queue_url" {
  value = var.enable_dlq ? aws_sqs_queue.failed_events[0].url : null
}

output "subscription_filter_names" {
  value = { for service, filter in aws_cloudwatch_log_subscription_filter.ecs : service => filter.name }
}
