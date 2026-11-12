output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_version" {
  description = "EKS Kubernetes version"
  value       = aws_eks_cluster.main.version
}

output "cluster_endpoint" {
  description = "EKS API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_security_group_id" {
  description = "Security group created by EKS for the cluster and managed nodes"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider for the EKS cluster"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "private_subnet_ids" {
  description = "EKS private subnets by availability zone"
  value       = { for zone, subnet in aws_subnet.private : zone => subnet.id }
}

output "node_group_names" {
  description = "Managed EKS node groups by workload class"
  value       = { for name, group in aws_eks_node_group.main : name => group.node_group_name }
}
