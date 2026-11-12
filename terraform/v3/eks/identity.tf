/** Pod identities
 * 애플리케이션과 ESO의 ServiceAccount를 기존 IAM 역할에 연결한다.
 */
locals {
  pod_identities = {
    external-secrets = {
      namespace = "external-secrets"
      role_arn  = aws_iam_role.external_secrets.arn
    }
    auth-api = {
      namespace = "auth"
      role_arn  = aws_iam_role.application_s3.arn
    }
    user-api = {
      namespace = "user"
      role_arn  = aws_iam_role.application_s3.arn
    }
    onboarding-api = {
      namespace = "user"
      role_arn  = aws_iam_role.application_s3.arn
    }
    recommend-api = {
      namespace = "recommend"
      role_arn  = aws_iam_role.application_s3.arn
    }
    chat-api = {
      namespace = "chat"
      role_arn  = aws_iam_role.application_s3.arn
    }
    chat-socket = {
      namespace = "chat"
      role_arn  = aws_iam_role.application_s3.arn
    }
  }
}

resource "aws_eks_pod_identity_association" "main" {
  for_each = local.pod_identities

  cluster_name         = aws_eks_cluster.main.name
  namespace            = each.value.namespace
  service_account      = each.key
  role_arn             = each.value.role_arn
  disable_session_tags = false
}
