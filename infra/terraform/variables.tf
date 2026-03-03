variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "cicd-control-plane"
}

variable "eks_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "node_groups" {
  description = "EKS node groups configuration"
  type = map(object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
    disk_size      = number
    capacity_type  = string
  }))
  
  default = {
    general = {
      instance_types = ["t3.large"]
      min_size       = 2
      max_size       = 5
      desired_size   = 3
      disk_size      = 50
      capacity_type  = "ON_DEMAND"
    }
    spot = {
      instance_types = ["t3.large", "t3a.large"]
      min_size       = 0
      max_size       = 10
      desired_size   = 2
      disk_size      = 50
      capacity_type  = "SPOT"
    }
  }
}

variable "ecr_repositories" {
  description = "ECR repositories to create"
  type        = list(string)
  default     = ["sample-app", "jenkins-agent"]
}