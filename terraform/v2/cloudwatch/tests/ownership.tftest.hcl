mock_provider "aws" {
  mock_data "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:ap-northeast-2:975779326240:log-group:/ecs/star23/prod/be:*" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_region" { defaults = { region = "ap-northeast-2" } }
  mock_data "aws_partition" { defaults = { partition = "aws", dns_suffix = "amazonaws.com" } }
  mock_data "aws_caller_identity" { defaults = { account_id = "975779326240" } }
  mock_data "aws_subnet" { defaults = { vpc_id = "vpc-0123456789abcdef0" } }
}
variables {
  monitoring_ami_id              = "ami-0123456789abcdef0"
  monitoring_vpc_id              = "vpc-0123456789abcdef0"
  monitoring_subnet_id           = "subnet-0123456789abcdef0"
  monitoring_ssh_cidrs           = []
  monitoring_grafana_admin_cidrs = []
}
run "fresh_logging_infrastructure" {
  command = plan
  variables {
    enable_function_connections = false
    enable_failure_queue        = true
  }
  assert {
    condition     = length(output.subscription_filter_names) == 0
    error_message = "Fresh logging must wait for external Lambda creation before wiring subscriptions."
  }
}
run "external_function_connections" {
  command = plan
  assert {
    condition     = output.function_arn == "arn:aws:lambda:ap-northeast-2:975779326240:function:star23-prod-cloudwatch-loki" && length(output.subscription_filter_names) == 3
    error_message = "Subscriptions must retain the existing external Lambda ARN and all three source groups."
  }
}
