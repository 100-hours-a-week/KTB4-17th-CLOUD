# Preserve existing state addresses when moving resources into modules.
# Keep this migration history for existing environments.

moved {
  from = aws_cloudfront_distribution.fe
  to   = module.cdn.aws_cloudfront_distribution.fe
}

moved {
  from = aws_alb.main
  to   = module.alb.aws_alb.main
}

moved {
  from = aws_lb_listener_rule.ws
  to   = module.alb.aws_lb_listener_rule.ws
}

moved {
  from = aws_lb_listener.https
  to   = module.alb.aws_lb_listener.https
}

moved {
  from = aws_lb_listener.http
  to   = module.alb.aws_lb_listener.http
}

moved {
  from = aws_lb_target_group.api
  to   = module.alb.aws_lb_target_group.api
}

moved {
  from = aws_lb_target_group.ws
  to   = module.alb.aws_lb_target_group.ws
}

moved {
  from = aws_iam_role.ecs_execution
  to   = module.ecs.aws_iam_role.ecs_execution
}

moved {
  from = aws_iam_role_policy_attachment.ecs_execution
  to   = module.ecs.aws_iam_role_policy_attachment.ecs_execution
}

moved {
  from = aws_iam_role.ecs_task
  to   = module.ecs.aws_iam_role.ecs_task
}

moved {
  from = aws_iam_role_policy.ecs_execution_secrets
  to   = module.ecs.aws_iam_role_policy.ecs_execution_secrets
}

moved {
  from = aws_iam_role_policy.ecs_execution_secret_kms
  to   = module.ecs.aws_iam_role_policy.ecs_execution_secret_kms
}

moved {
  from = aws_iam_role.service_execution
  to   = module.ecs.aws_iam_role.service_execution
}

moved {
  from = aws_iam_role_policy_attachment.service_execution
  to   = module.ecs.aws_iam_role_policy_attachment.service_execution
}

moved {
  from = aws_iam_role.service_task
  to   = module.ecs.aws_iam_role.service_task
}

moved {
  from = aws_iam_role_policy.service_execution_secrets
  to   = module.ecs.aws_iam_role_policy.service_execution_secrets
}

moved {
  from = aws_iam_role_policy.service_execution_secret_kms
  to   = module.ecs.aws_iam_role_policy.service_execution_secret_kms
}

moved {
  from = aws_iam_role_policy.be_s3
  to   = module.ecs.aws_iam_role_policy.be_s3
}

moved {
  from = aws_ecs_cluster.main
  to   = module.ecs.aws_ecs_cluster.main
}

moved {
  from = aws_service_discovery_http_namespace.ecs
  to   = module.ecs.aws_service_discovery_http_namespace.ecs
}

moved {
  from = aws_ssm_parameter.be_config
  to   = module.ecs.aws_ssm_parameter.be_config
}

moved {
  from = aws_secretsmanager_secret.be
  to   = module.ecs.aws_secretsmanager_secret.be
}

moved {
  from = aws_secretsmanager_secret_version.be
  to   = module.ecs.aws_secretsmanager_secret_version.be
}

moved {
  from = aws_ecs_task_definition.be
  to   = module.ecs.aws_ecs_task_definition.be
}

moved {
  from = aws_ecs_service.be
  to   = module.ecs.aws_ecs_service.be
}

moved {
  from = aws_ecs_task_definition.ws
  to   = module.ecs.aws_ecs_task_definition.ws
}

moved {
  from = aws_ecs_service.ws
  to   = module.ecs.aws_ecs_service.ws
}

moved {
  from = aws_ecs_task_definition.ai
  to   = module.ecs.aws_ecs_task_definition.ai
}

moved {
  from = aws_ecs_service.ai
  to   = module.ecs.aws_ecs_service.ai
}

moved {
  from = aws_ecr_repository.ai
  to   = module.storage.aws_ecr_repository.ai
}

moved {
  from = aws_ecr_repository.be
  to   = module.storage.aws_ecr_repository.be
}

moved {
  from = aws_s3_bucket.image
  to   = module.storage.aws_s3_bucket.image
}

moved {
  from = aws_s3_bucket.fe
  to   = module.storage.aws_s3_bucket.fe
}
