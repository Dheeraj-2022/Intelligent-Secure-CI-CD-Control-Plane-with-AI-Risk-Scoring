# =============================================================================
# IRSA Module — outputs.tf
# =============================================================================

output "role_arn" {
  description = "ARN of the IRSA IAM role"
  value       = aws_iam_role.irsa.arn
}

output "role_name" {
  description = "Name of the IRSA IAM role"
  value       = aws_iam_role.irsa.name
}
