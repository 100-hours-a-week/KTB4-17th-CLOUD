# ECS Execution Role(기동)과 Task Role(앱 API 호출)의 권한.
# Terraform 실행자와 GitHub 배포 역할은 이 모듈의 관리 대상이 아니다.

data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${var.name_prefix}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    Name        = "${var.name_prefix}-ecs-execution-role"
    environment = "prod"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name               = "${var.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    Name        = "${var.name_prefix}-ecs-task-role"
    environment = "prod"
  }
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  count = 1

  name = "${var.name_prefix}-ecs-execution-secrets"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      length(var.be_environment) > 0 ? [{
        Effect   = "Allow"
        Action   = ["ssm:GetParameters"]
        Resource = [for parameter in aws_ssm_parameter.be_config : parameter.arn]
      }] : [],
      [{
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        # JSON key/version 선택자는 IAM 리소스 ARN에서 제외한다.
        Resource = distinct([
          for value_from in values(local.be_secret_references) :
          join(":", slice(split(":", value_from), 0, 7))
        ])
      }]
    )
  })
}

resource "aws_iam_role_policy" "ecs_execution_secret_kms" {
  count = length(var.be_secret_kms_key_arns) > 0 ? 1 : 0

  name = "${var.name_prefix}-ecs-execution-secret-kms"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = var.be_secret_kms_key_arns
    }]
  })
}

resource "aws_iam_role" "service_execution" {
  for_each = local.additional_ecs_services

  name               = "${var.name_prefix}-${each.key}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    Name        = "${var.name_prefix}-${each.key}-ecs-execution-role"
    environment = "prod"
  }
}

resource "aws_iam_role_policy_attachment" "service_execution" {
  for_each = local.additional_ecs_services

  role       = aws_iam_role.service_execution[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "service_task" {
  for_each = local.additional_ecs_services

  name               = "${var.name_prefix}-${each.key}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    Name        = "${var.name_prefix}-${each.key}-ecs-task-role"
    environment = "prod"
  }
}

resource "aws_iam_role_policy" "service_execution_secrets" {
  for_each = {
    for name, settings in local.additional_ecs_services : name => settings
    if length(settings.secrets) > 0
  }

  name = "${var.name_prefix}-${each.key}-ecs-execution-secrets"
  role = aws_iam_role.service_execution[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for value_from in values(each.value.secrets) : {
        Effect   = "Allow"
        Action   = startswith(value_from, "arn:aws:secretsmanager:") ? ["secretsmanager:GetSecretValue"] : ["ssm:GetParameters"]
        Resource = startswith(value_from, "arn:aws:secretsmanager:") ? join(":", slice(split(":", value_from), 0, 7)) : value_from
      }
    ]
  })
}

resource "aws_iam_role_policy" "service_execution_secret_kms" {
  for_each = {
    for name, settings in local.additional_ecs_services : name => settings
    if length(settings.kms_key_arns) > 0
  }

  name = "${var.name_prefix}-${each.key}-ecs-execution-secret-kms"
  role = aws_iam_role.service_execution[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = each.value.kms_key_arns
    }]
  })
}

resource "aws_iam_role_policy" "be_s3" {
  name = "${var.name_prefix}-be-s3"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Resource = "${var.image_bucket_arn}/*"
    }]
  })
}

resource "aws_iam_role_policy" "ws_s3" {
  count = var.ws_enabled && var.ws_use_backend_config ? 1 : 0

  name = "${var.name_prefix}-ws-s3"
  role = aws_iam_role.service_task["ws"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Resource = "${var.image_bucket_arn}/*"
    }]
  })
}
