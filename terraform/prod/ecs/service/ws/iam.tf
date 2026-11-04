data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "service_execution" {
  for_each = local.additional_ecs_services

  name               = "${var.name_prefix}-${each.key}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    Name        = "${var.name_prefix}-${each.key}-ecs-execution-role"
    environment = var.environment
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
    environment = var.environment
  }
}

resource "aws_iam_role_policy" "service_execution_secrets" {
  for_each = {
    for name, settings in local.additional_ecs_services : name => settings
    if length(settings.secrets) > 0 || (name == "ai" && length([]) > 0)
  }

  name = "${var.name_prefix}-${each.key}-ecs-execution-secrets"
  role = aws_iam_role.service_execution[each.key].id

  # Preserve the consolidated live AI policy and the WS statement structure.
  policy = each.key == "ai" && alltrue([for value_from in values(each.value.secrets) : startswith(value_from, "arn:aws:secretsmanager:")]) ? jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = distinct(concat([
        for value_from in values(each.value.secrets) :
        join(":", slice(split(":", value_from), 0, 7))
      ], tolist([])))
    }]
    }) : jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      for value_from in values(each.value.secrets) : {
        Effect   = "Allow"
        Action   = startswith(value_from, "arn:aws:secretsmanager:") ? ["secretsmanager:GetSecretValue"] : ["ssm:GetParameters"]
        Resource = startswith(value_from, "arn:aws:secretsmanager:") ? join(":", slice(split(":", value_from), 0, 7)) : value_from
      }
      ], each.key == "ai" && length([]) > 0 ? [{
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = tolist([])
    }] : [])
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
