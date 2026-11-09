terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

/**
 * AWS context
 */
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

/**
 * Source log groups
 *
 * ECS에서 관리하는 로그 그룹을 조회해 구독 대상으로 사용한다.
 */
data "aws_cloudwatch_log_group" "source" {
  for_each = var.log_groups
  name     = each.value
}

/**
 * Forwarder settings
 */
locals {
  function_arn = "arn:${data.aws_partition.current.partition}:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:function:${var.name}"
  tags         = merge(var.tags, { Name = var.name, environment = "prod" })
  eni_actions = [
    "ec2:CreateNetworkInterface",
    "ec2:DescribeNetworkInterfaces",
    "ec2:DescribeSubnets",
    "ec2:DeleteNetworkInterface",
    "ec2:AssignPrivateIpAddresses",
    "ec2:UnassignPrivateIpAddresses",
  ]
}

/**
 * Forwarder logs
 *
 * 전달 함수 자체의 실행 로그를 보관한다.
 */
resource "aws_cloudwatch_log_group" "forwarder" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.lambda_log_retention_days
  tags              = local.tags
}

/**
 * Failure queue
 *
 * DLQ를 켠 경우 실패한 비동기 호출 이벤트를 보관할 큐를 만든다.
 */
resource "aws_sqs_queue" "failed_events" {
  count = var.enable_dlq ? 1 : 0

  name                      = "${var.name}-failed-events"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
  tags                      = local.tags
}

/**
 * Execution role
 *
 * Lambda 서비스가 이 역할을 맡을 수 있도록 신뢰 정책을 연결한다.
 */
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

/**
 * Execution permissions
 *
 * 실행 역할에 로그 기록·VPC 인터페이스 관리·선택적 DLQ 전송 권한을 연결한다.
 */
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

/**
 * External function connections
 *
 * 외부 Lambda의 호출 권한과 재시도 설정이 준비된 뒤 로그 구독을 연결한다.
 */
resource "aws_lambda_function_event_invoke_config" "forwarder" {
  count                        = var.enable_function_connections ? 1 : 0
  function_name                = var.name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 3600
}

resource "aws_lambda_permission" "cloudwatch" {
  for_each = var.enable_function_connections ? var.log_groups : {}

  statement_id   = "AllowCloudWatch-${each.key}"
  action         = "lambda:InvokeFunction"
  function_name  = var.name
  principal      = "logs.${data.aws_region.current.region}.${data.aws_partition.current.dns_suffix}"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = "${trimsuffix(data.aws_cloudwatch_log_group.source[each.key].arn, ":*")}:*"
}

resource "aws_cloudwatch_log_subscription_filter" "ecs" {
  for_each = var.enable_function_connections ? var.log_groups : {}

  name            = "${var.name}-${each.key}"
  log_group_name  = each.value
  filter_pattern  = ""
  destination_arn = local.function_arn

  depends_on = [
    aws_lambda_permission.cloudwatch,
    aws_lambda_function_event_invoke_config.forwarder,
  ]
}
