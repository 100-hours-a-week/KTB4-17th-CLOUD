/** Node groups
 * 워크로드별 인스턴스 종류와 현재 노드 수를 정의한다.
 */
locals {
  node_groups = {
    cpu = {
      instance_type = "c4.large"
      capacity_type = "ON_DEMAND"
      ami_type      = "AL2023_x86_64_STANDARD"
      desired_size  = 1
      min_size      = 0
      max_size      = 1
    }
    general = {
      instance_type = "t3.2xlarge"
      capacity_type = "ON_DEMAND"
      ami_type      = "AL2023_x86_64_STANDARD"
      desired_size  = 1
      min_size      = 1
      max_size      = 2
    }
    gpu = {
      instance_type = "g4dn.xlarge"
      capacity_type = "ON_DEMAND"
      ami_type      = "AL2023_x86_64_NVIDIA"
      desired_size  = 0
      min_size      = 0
      max_size      = 1
    }
    spot = {
      instance_type = "t3.medium"
      capacity_type = "SPOT"
      ami_type      = "AL2023_x86_64_STANDARD"
      desired_size  = 0
      min_size      = 0
      max_size      = 1
    }
  }
}

/** Managed nodes
 * ASG와 Launch Template은 EKS가 노드그룹의 하위 자원으로 관리한다.
 */
resource "aws_eks_node_group" "main" {
  for_each = local.node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = [for subnet in aws_subnet.private : subnet.id]
  version         = aws_eks_cluster.main.version
  release_version = "1.37.1-20261031"
  ami_type        = each.value.ami_type
  capacity_type   = each.value.capacity_type
  instance_types  = [each.value.instance_type]
  disk_size       = 20

  labels = {
    workload-class = each.key
  }

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  update_config {
    max_unavailable = 1
  }

  /** Node scaling
   * 최소·최대는 Terraform, 실행 수는 Cluster Autoscaler가 관리한다.
   */
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [
    aws_route.private_nat,
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_minimal,
    aws_iam_role_policy_attachment.node_ecr_pull,
    aws_iam_role_policy_attachment.node_ecr_public,
  ]
}
