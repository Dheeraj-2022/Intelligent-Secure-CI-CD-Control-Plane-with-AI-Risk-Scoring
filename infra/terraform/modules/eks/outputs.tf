# =============================================================================
# EKS Module — outputs.tf
# =============================================================================

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "API server endpoint URL"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority" {
  description = "Base64-encoded certificate authority data"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version of the cluster"
  value       = aws_eks_cluster.main.version
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider (required for IRSA)"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL (without https://)"
  value       = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}

output "node_role_arn" {
  description = "ARN of the IAM role used by EKS worker nodes"
  value       = aws_iam_role.node.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for secret encryption"
  value       = aws_kms_key.eks.arn
}
