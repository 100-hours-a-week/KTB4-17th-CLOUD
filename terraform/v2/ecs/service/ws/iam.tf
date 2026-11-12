/**
 * WS task trust
 */
data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

/**
 * WS execution role
 *
 * ECS가 이미지 다운로드와 로그 전송에 사용하는 역할이다.
 */
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

/**
 * WS task role
 *
 * 컨테이너 안의 애플리케이션이 AWS API를 호출할 때 사용하는 역할이다.
 */
resource "aws_iam_role" "service_task" {
  for_each = local.additional_ecs_services

  name               = "${var.name_prefix}-${each.key}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    Name        = "${var.name_prefix}-${each.key}-ecs-task-role"
    environment = var.environment
  }
}

/**
 * WS secret access
 *
 * 각 Secret·SSM ARN에 필요한 읽기 권한을 부여하며, 실제 값은 조회하지 않는다.
 */
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

/**
 * WS secret decryption
 *
 * 지정한 KMS 키로 암호화된 시크릿을 읽는 데 필요한 복호화 권한이다.
 */
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

/**
 * WS storage access
 */
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

/** WS Kafka and Redis permissions
 * 기존 파라미터 ARN과 KMS 조건만 보존하며 실제 앱 설정값은 읽지 않는다.
 */
resource "aws_iam_role_policy" "kafka_redis_parameters" {
  for_each = local.additional_ecs_services

  name = "Star23ProdKafkaRedisParameters"
  role = aws_iam_role.service_execution[each.key].id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "ReadProdWsKafkaRedisParameters",
        "Effect" : "Allow",
        "Action" : "ssm:GetParameters",
        "Resource" : [
          "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/kafka-redis/ws/KAFKA_BOOTSTRAP_SERVERS",
          "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/kafka-redis/ws/REDIS_URL"
        ]
      },
      {
        "Sid" : "DecryptProdWsRedisUrl",
        "Effect" : "Allow",
        "Action" : "kms:Decrypt",
        "Resource" : "arn:aws:kms:ap-northeast-2:975779326240:key/c46fdb44-b0c9-4743-aad9-a71eab8d5ff9",
        "Condition" : {
          "StringEquals" : {
            "kms:ViaService" : "ssm.ap-northeast-2.amazonaws.com",
            "kms:EncryptionContext:PARAMETER_ARN" : "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/kafka-redis/ws/REDIS_URL"
          }
        }
      }
    ]
  })
}

/** WS migration policy attachment
 * 공유 마이그레이션 정책을 현재 실행 역할에 연결하며 Secret·SSM 값은 관리하지 않는다.
 */
resource "aws_iam_role_policy_attachment" "migration_runtime_parameters" {
  for_each = local.additional_ecs_services

  role       = aws_iam_role.service_execution[each.key].name
  policy_arn = var.migration_policy_arn
}
