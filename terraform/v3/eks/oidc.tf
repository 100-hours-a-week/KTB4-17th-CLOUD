/** Cluster OIDC provider
 * 현재 EKS issuer와 지문을 보존하며 ALB·Autoscaler IRSA 신뢰에서 참조한다.
 */
locals {
  oidc_issuer = trimprefix(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://")
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["06b25927c42a721631c1efd9431e648fa62e1e39"]
  tags            = {}
}
