/** Cluster principals
 * 노드와 운영 주체의 기존 EKS 접근 엔트리를 보존한다.
 */
locals {
  access_entries = {
    account_root = {
      principal_arn     = "arn:aws:iam::975779326240:root"
      type              = "STANDARD"
      kubernetes_groups = []
    }
    eks_service = {
      principal_arn     = "arn:aws:iam::975779326240:role/aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS"
      type              = "STANDARD"
      kubernetes_groups = ["eks:managed"]
    }
    node = {
      principal_arn     = aws_iam_role.node.arn
      type              = "EC2_LINUX"
      kubernetes_groups = null
    }
    fargate = {
      principal_arn     = "arn:aws:iam::975779326240:role/AmazonEKSFargatePodExecutionRole-star-EKS-v3"
      type              = "FARGATE_LINUX"
      kubernetes_groups = null
    }
  }

  access_policies = {
    cluster_admin = {
      entry      = "account_root"
      policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    }
    cluster_insights = {
      entry      = "eks_service"
      policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterInsightsPolicy"
    }
    events = {
      entry      = "eks_service"
      policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEventPolicy"
    }
    pod_identity = {
      entry      = "eks_service"
      policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSPodIdentityPolicy"
    }
  }
}

/** Access entries
 * EC2와 Fargate의 사용자명과 그룹은 EKS가 정한다.
 */
resource "aws_eks_access_entry" "main" {
  for_each = local.access_entries

  cluster_name      = aws_eks_cluster.main.name
  principal_arn     = each.value.principal_arn
  type              = each.value.type
  kubernetes_groups = each.value.kubernetes_groups
}

/** Access policies
 * 기존 네 개 정책 연결의 범위를 클러스터 전체로 유지한다.
 */
resource "aws_eks_access_policy_association" "main" {
  for_each = local.access_policies

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_eks_access_entry.main[each.value.entry].principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type = "cluster"
  }
}
