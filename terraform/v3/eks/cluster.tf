/** EKS cluster
 * 기존 클러스터의 네트워크와 접근 설정을 유지한다.
 */
resource "aws_eks_cluster" "main" {
  name                      = "star-EKS-v3"
  role_arn                  = aws_iam_role.cluster.arn
  version                   = "1.37"
  deletion_protection       = true
  enabled_cluster_log_types = []

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids                = [for subnet in aws_subnet.private : subnet.id]
    security_group_ids        = []
    endpoint_private_access   = true
    endpoint_public_access    = true
    public_access_cidrs       = ["0.0.0.0/0"]
    control_plane_egress_mode = "AWS_MANAGED"
  }

  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = "172.20.0.0/16"

    elastic_load_balancing {
      enabled = false
    }
  }

  control_plane_scaling_config {
    tier = "standard"
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  zonal_shift_config {
    enabled = false
  }

  tags = {
    Project = "star23sharp"
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}
