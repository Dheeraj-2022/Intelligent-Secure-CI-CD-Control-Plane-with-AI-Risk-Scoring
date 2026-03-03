# =============================================================================
# IRSA Module — variables.tf
# IAM Roles for Service Accounts (IRSA) on EKS
# =============================================================================

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider associated with the EKS cluster"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the service account"
  type        = string
}

variable "service_account" {
  description = "Name of the Kubernetes service account to bind"
  type        = string
}

variable "policy_arns" {
  description = "List of IAM managed policy ARNs to attach to the role"
  type        = list(string)
  default     = []
}

variable "inline_policy" {
  description = "Optional inline IAM policy document (JSON string)"
  type        = string
  default     = ""
}
