terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_cloudwatch_log_group" "source" {
  for_each = var.log_groups
  name     = each.value
}

locals {
  function_arn = "arn:${data.aws_partition.current.partition}:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:function:${var.name}"
  tags         = merge(var.tags, { Name = var.name, environment = "prod" })
  labels       = merge(var.extra_labels, { environment = "prod", job = "ecs", source = "cloudwatch" })

  # v1.0.1 omits ScratchBuilder.Sort() before relabeling a Go map.
  # Keep only the CloudWatch group as input (one label is always sorted), then
  # add constants through relabeling instead of the EXTRA_LABELS map.
  # https://github.com/grafana/lambda-promtail/blob/v1.0.1/pkg/main.go#L185-L200
  relabel_configs = jsonencode(concat([
    {
      source_labels = ["__aws_cloudwatch_log_group"]
      regex         = "/ecs/[^/]+/prod/(be|ws|ai)"
      target_label  = "service"
      replacement   = "$1"
      action        = "replace"
    },
    {
      source_labels = ["service"]
      regex         = "be"
      target_label  = "service"
      replacement   = "spring"
      action        = "replace"
    },
    {
      source_labels = ["__aws_cloudwatch_log_group"]
      regex         = "/ecs/([^/]+)/prod/(be|ws|ai)"
      target_label  = "ecs_service"
      replacement   = "$1-$2-service"
      action        = "replace"
    },
    {
      source_labels = ["__aws_cloudwatch_log_group"]
      target_label  = "cloudwatch_log_group"
      action        = "replace"
    },
    {
      regex  = "__aws_.*"
      action = "labeldrop"
    }
    ], [for name in sort(keys(local.labels)) : {
      action       = "replace"
      target_label = name
      replacement  = replace(local.labels[name], "$", "$$")
  }]))

  eni_actions = [
    "ec2:CreateNetworkInterface",
    "ec2:DescribeNetworkInterfaces",
    "ec2:DescribeSubnets",
    "ec2:DeleteNetworkInterface",
    "ec2:AssignPrivateIpAddresses",
    "ec2:UnassignPrivateIpAddresses",
  ]
}

resource "aws_security_group" "forwarder" {
  name        = var.name
  description = "CloudWatch log forwarder: outbound only to private Loki"
  vpc_id      = var.vpc_id
  tags        = local.tags
}

resource "aws_vpc_security_group_egress_rule" "to_loki" {
  security_group_id            = aws_security_group.forwarder.id
  referenced_security_group_id = var.loki_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 3100
  to_port                      = 3100
  description                  = "Lambda-promtail to Loki HTTP only"
  tags                         = local.tags
}

# A separate rule preserves the existing Loki group's other rules.
resource "aws_vpc_security_group_ingress_rule" "loki_from_forwarder" {
  security_group_id            = var.loki_security_group_id
  referenced_security_group_id = aws_security_group.forwarder.id
  ip_protocol                  = "tcp"
  from_port                    = 3100
  to_port                      = 3100
  description                  = "CloudWatch Lambda log forwarder"
  tags                         = local.tags
}

resource "aws_cloudwatch_log_group" "forwarder" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.lambda_log_retention_days
  tags              = local.tags
}

resource "aws_sqs_queue" "failed_events" {
  count = var.enable_dlq ? 1 : 0

  name                      = "${var.name}-failed-events"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
  tags                      = local.tags
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

resource "aws_iam_role" "forwarder" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = local.tags
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "WriteOwnLogStreams"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${trimsuffix(aws_cloudwatch_log_group.forwarder.arn, ":*")}:*"]
  }

  statement {
    sid     = "ManageLambdaVpcInterfaces"
    actions = local.eni_actions
    # AWS requires Resource=* for the VPC execution role's ENI operations.
    # https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [data.aws_region.current.region]
    }
  }

  statement {
    sid       = "DenyFunctionCodeVpcChanges"
    effect    = "Deny"
    actions   = local.eni_actions
    resources = ["*"]

    # Service-side ENI provisioning has no SourceFunctionArn; function code does.
    condition {
      test     = "ArnEquals"
      variable = "lambda:SourceFunctionArn"
      values   = [local.function_arn]
    }
  }

  dynamic "statement" {
    for_each = var.enable_dlq ? [1] : []
    content {
      sid       = "SendFailedInvocationsOnly"
      actions   = ["sqs:SendMessage"]
      resources = [aws_sqs_queue.failed_events[0].arn]
    }
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "${var.name}-execution"
  role   = aws_iam_role.forwarder.id
  policy = data.aws_iam_policy_document.execution.json
}

resource "aws_lambda_function" "forwarder" {
  function_name = var.name
  description   = "Forward production ECS CloudWatch log batches to private Loki"
  role          = aws_iam_role.forwarder.arn

  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)
  package_type     = "Zip"
  runtime          = "provided.al2023"
  architectures    = ["x86_64"]
  handler          = "bootstrap"

  timeout                        = 60
  memory_size                    = 256
  reserved_concurrent_executions = var.reserved_concurrency

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.forwarder.id]
  }

  dynamic "dead_letter_config" {
    for_each = var.enable_dlq ? [1] : []
    content {
      target_arn = aws_sqs_queue.failed_events[0].arn
    }
  }

  environment {
    variables = {
      WRITE_ADDRESS            = var.loki_write_address
      EXTRA_LABELS             = ""
      DROP_LABELS              = "__aws_log_type,__aws_cloudwatch_owner"
      OMIT_EXTRA_LABELS_PREFIX = "true"
      RELABEL_CONFIGS          = local.relabel_configs
      KEEP_STREAM              = "false"
      PRINT_LOG_LINE           = "false"
      LOG_LEVEL                = "info"
    }
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = filesha256(var.lambda_zip_path) == var.lambda_zip_sha256
      error_message = "Lambda ZIP does not match the expected, verified upstream artifact checksum."
    }
  }

  depends_on = [
    aws_iam_role_policy.execution,
    aws_cloudwatch_log_group.forwarder,
    aws_vpc_security_group_egress_rule.to_loki,
    aws_vpc_security_group_ingress_rule.loki_from_forwarder,
  ]
}

resource "aws_lambda_function_event_invoke_config" "forwarder" {
  function_name                = aws_lambda_function.forwarder.function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 3600
}

resource "aws_lambda_permission" "cloudwatch" {
  for_each = var.log_groups

  statement_id   = "AllowCloudWatch-${each.key}"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.forwarder.function_name
  principal      = "logs.${data.aws_region.current.region}.${data.aws_partition.current.dns_suffix}"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = "${trimsuffix(data.aws_cloudwatch_log_group.source[each.key].arn, ":*")}:*"
}

resource "aws_cloudwatch_log_subscription_filter" "ecs" {
  for_each = var.log_groups

  name            = "${var.name}-${each.key}"
  log_group_name  = each.value
  filter_pattern  = ""
  destination_arn = aws_lambda_function.forwarder.arn

  depends_on = [
    aws_lambda_permission.cloudwatch,
    aws_lambda_function_event_invoke_config.forwarder,
  ]
}
