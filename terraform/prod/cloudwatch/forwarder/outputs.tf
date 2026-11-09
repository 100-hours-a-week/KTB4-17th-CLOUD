output "function_name" {
  value = var.name
}

output "function_arn" {
  value = local.function_arn
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

output "deployment_infrastructure" {
  value = {
    function_name          = var.name
    function_arn           = local.function_arn
    execution_role_arn     = aws_iam_role.forwarder.arn
    subnet_ids             = var.subnet_ids
    security_group_ids     = [aws_security_group.forwarder.id]
    log_group_name         = aws_cloudwatch_log_group.forwarder.name
    dead_letter_target_arn = try(aws_sqs_queue.failed_events[0].arn, null)
  }
}
