# =============================================================================
# VPC Module — variables.tf
# =============================================================================

variable "cluster_name" {
  description = "EKS cluster name used to tag VPC resources for auto-discovery"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "List of availability zones to create subnets in"
  type        = list(string)
}
