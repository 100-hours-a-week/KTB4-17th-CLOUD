/** Migration runtime permissions
 * BE·WS가 공유하는 현재 파라미터 읽기 권한과 KMS 조건을 그대로 보존한다.
 */
resource "aws_iam_policy" "migration_runtime_parameters" {
  name        = "Star23MigrationRuntimeParameters"
  path        = "/"
  description = "Read and decrypt only the explicitly approved production migration runtime parameters"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "ReadMigrationRuntime",
        "Effect" : "Allow",
        "Action" : "ssm:GetParameters",
        "Resource" : [
          "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/rabbitmq/RABBITMQ_HOST",
          "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/rabbitmq/RABBITMQ_PORT",
          "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/rabbitmq/RABBITMQ_STOMP_PORT",
          "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/rabbitmq/RABBITMQ_USERNAME",
          "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/rabbitmq/RABBITMQ_PASSWORD",
          "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/rabbitmq/RABBITMQ_VHOST",
          "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/rabbitmq/RABBITMQ_CHAT_EXCHANGE",
          "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/be/KAKAO_TALK_PROFILE_URI"
        ]
      },
      {
        "Sid" : "DecryptMigrationParameters",
        "Effect" : "Allow",
        "Action" : "kms:Decrypt",
        "Resource" : "arn:aws:kms:ap-northeast-2:975779326240:key/c46fdb44-b0c9-4743-aad9-a71eab8d5ff9",
        "Condition" : {
          "StringEquals" : {
            "kms:ViaService" : "ssm.ap-northeast-2.amazonaws.com"
          },
          "StringLike" : {
            "kms:EncryptionContext:PARAMETER_ARN" : [
              "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/rabbitmq/RABBITMQ_HOST",
              "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/rabbitmq/RABBITMQ_PORT",
              "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/rabbitmq/RABBITMQ_STOMP_PORT",
              "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/rabbitmq/RABBITMQ_USERNAME",
              "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/rabbitmq/RABBITMQ_PASSWORD",
              "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/rabbitmq/RABBITMQ_VHOST",
              "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/migration/rabbitmq/RABBITMQ_CHAT_EXCHANGE"
            ]
          }
        }
      }
    ]
  })
  tags = { "Purpose" : "production-migration-readiness" }
}
