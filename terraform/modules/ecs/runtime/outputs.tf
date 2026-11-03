output "execution_role_arn" {
  value      = try(aws_iam_role.service_execution[var.service_name].arn, null)
  depends_on = [aws_iam_role_policy_attachment.service_execution, aws_iam_role_policy.service_execution_secrets, aws_iam_role_policy.service_execution_secret_kms]
}
output "task_role_arn" { value = try(aws_iam_role.service_task[var.service_name].arn, null) }
output "task_role_id" { value = try(aws_iam_role.service_task[var.service_name].id, null) }
output "security_group_id" {
  value      = aws_security_group.service.id
  depends_on = [aws_vpc_security_group_egress_rule.outbound]
}
output "log_group_name" { value = try(aws_cloudwatch_log_group.service[0].name, null) }
