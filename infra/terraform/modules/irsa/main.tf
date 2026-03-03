# =============================================================================
# IRSA Module — main.tf
# Creates an IAM role that can be assumed by a specific Kubernetes service
# account via OIDC federation (IAM Roles for Service Accounts).
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  # Strip https:// from the OIDC provider ARN to build the condition key
  oidc_issuer = replace(var.oidc_provider_arn, "/^arn:aws:iam::[0-9]+:oidc-provider\\//", "")
}

# ─── IAM Role ─────────────────────────────────────────────────────────────────
resource "aws_iam_role" "irsa" {
  name        = "${var.cluster_name}-${var.namespace}-${var.service_account}-irsa"
  description = "IRSA role for ${var.service_account} in namespace ${var.namespace}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account}"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    "eks-cluster"       = var.cluster_name
    "k8s-namespace"     = var.namespace
    "k8s-service-account" = var.service_account
  }
}

# ─── Managed policy attachments ───────────────────────────────────────────────
resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.policy_arns)

  role       = aws_iam_role.irsa.name
  policy_arn = each.value
}

# ─── Inline policy (optional) ─────────────────────────────────────────────────
resource "aws_iam_role_policy" "inline" {
  count = var.inline_policy != "" ? 1 : 0

  name   = "${var.cluster_name}-${var.service_account}-inline"
  role   = aws_iam_role.irsa.id
  policy = var.inline_policy
}
