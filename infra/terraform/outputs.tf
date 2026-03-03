# =============================================================================
# Root Terraform Outputs — Intelligent Secure CI/CD Control Plane
# =============================================================================

# ─── VPC ──────────────────────────────────────────────────────────────────────
output "vpc_id" {
  description = "ID of the created VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.vpc.public_subnet_ids
}

# ─── EKS ──────────────────────────────────────────────────────────────────────
output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "API server endpoint for the EKS cluster"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "eks_cluster_certificate_authority" {
  description = "Base64-encoded certificate authority data for kubectl"
  value       = module.eks.cluster_certificate_authority
  sensitive   = true
}

output "eks_oidc_provider_arn" {
  description = "ARN of the OIDC provider (used for IRSA)"
  value       = module.eks.oidc_provider_arn
}

# ─── ECR ──────────────────────────────────────────────────────────────────────
output "ecr_repository_urls" {
  description = "Map of ECR repository name → URL"
  value       = module.ecr.repository_urls
}

# ─── IRSA ─────────────────────────────────────────────────────────────────────
output "jenkins_irsa_role_arn" {
  description = "IAM Role ARN for Jenkins service account (IRSA)"
  value       = module.jenkins_irsa.role_arn
}

output "argocd_irsa_role_arn" {
  description = "IAM Role ARN for ArgoCD service account (IRSA)"
  value       = module.argocd_irsa.role_arn
}

# ─── kubectl config ───────────────────────────────────────────────────────────
output "kubeconfig_command" {
  description = "AWS CLI command to update kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
