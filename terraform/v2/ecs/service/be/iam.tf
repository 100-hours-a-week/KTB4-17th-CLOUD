/**
 * BE task trust
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
 * BE execution role
 *
 * ECS가 이미지 다운로드와 로그 전송에 사용하는 역할이다.
 */
resource "aws_iam_role" "ecs_execution" {
  name               = "${var.name_prefix}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    Name        = "${var.name_prefix}-ecs-execution-role"
    environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

/**
 * BE task role
 *
 * 컨테이너 안의 애플리케이션이 AWS API를 호출할 때 사용하는 역할이다.
 */
resource "aws_iam_role" "ecs_task" {
  name               = "${var.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = {
    Name        = "${var.name_prefix}-ecs-task-role"
    environment = var.environment
  }
}

/**
 * BE secret access
 *
 * Secret·SSM ARN으로 읽기 권한을 제한하며, Terraform은 실제 값을 조회하지 않는다.
 */
resource "aws_iam_role_policy" "ecs_execution_secrets" {
  count = 1

  name = "${var.name_prefix}-ecs-execution-secrets"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      length(var.be_parameter_arns) > 0 ? [{
        Effect   = "Allow"
        Action   = ["ssm:GetParameters"]
        Resource = values(var.be_parameter_arns)
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

/**
 * BE secret decryption
 *
 * 지정한 KMS 키로 암호화된 시크릿을 읽는 데 필요한 복호화 권한이다.
 */
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

/**
 * BE storage access
 */
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

/** BE Kafka and Redis permissions
 * 기존 파라미터 ARN과 KMS 조건만 보존하며 실제 앱 설정값은 읽지 않는다.
 */
resource "aws_iam_role_policy" "kafka_redis_parameters" {
  name = "Star23ProdKafkaRedisParameters"
  role = aws_iam_role.ecs_execution.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "ReadProdBeKafkaRedisParameters",
        "Effect" : "Allow",
        "Action" : "ssm:GetParameters",
        "Resource" : [
          "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/kafka-redis/be/KAFKA_BOOTSTRAP_SERVERS",
          "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/kafka-redis/be/REDIS_URL"
        ]
      },
      {
        "Sid" : "DecryptProdBeRedisUrl",
        "Effect" : "Allow",
        "Action" : "kms:Decrypt",
        "Resource" : "arn:aws:kms:ap-northeast-2:975779326240:key/c46fdb44-b0c9-4743-aad9-a71eab8d5ff9",
        "Condition" : {
          "StringEquals" : {
            "kms:ViaService" : "ssm.ap-northeast-2.amazonaws.com",
            "kms:EncryptionContext:PARAMETER_ARN" : "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/kafka-redis/be/REDIS_URL"
          }
        }
      }
    ]
  })
}

/** BE migration policy attachment
 * 공유 마이그레이션 정책을 현재 실행 역할에 연결하며 Secret·SSM 값은 관리하지 않는다.
 */
resource "aws_iam_role_policy_attachment" "migration_runtime_parameters" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = var.migration_policy_arn
}
