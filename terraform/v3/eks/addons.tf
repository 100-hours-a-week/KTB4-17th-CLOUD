/** Managed add-ons
 * 운영 중인 버전을 고정하고 CNI의 Pod Identity도 애드온에서 관리한다.
 */
resource "aws_eks_addon" "main" {
  for_each = {
    coredns                = "v1.14.7-eksbuild.35"
    eks-pod-identity-agent = "v1.4.1-eksbuild.3"
    kube-proxy             = "v1.37.0-eksbuild.39"
    vpc-cni                = "v1.23.2-eksbuild.12"
  }

  cluster_name  = aws_eks_cluster.main.name
  addon_name    = each.key
  addon_version = each.value

  namespace_config {
    namespace = "kube-system"
  }

  dynamic "pod_identity_association" {
    for_each = each.key == "vpc-cni" ? [aws_iam_role.cni.arn] : []

    content {
      role_arn        = pod_identity_association.value
      service_account = "aws-node"
    }
  }

  depends_on = [aws_iam_role_policy_attachment.cni]
}
