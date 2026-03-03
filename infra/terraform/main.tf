terraform {
  required_version = ">= 1.6"
  
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "cicd-control-plane/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "CICD-Control-Plane"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"
  
  cluster_name = var.cluster_name
  vpc_cidr     = var.vpc_cidr
  azs          = var.availability_zones
}

# EKS Module
module "eks" {
  source = "./modules/eks"
  
  cluster_name    = var.cluster_name
  cluster_version = var.eks_version
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  
  node_groups = var.node_groups
}

# ECR Module
module "ecr" {
  source = "./modules/ecr"
  
  repositories = var.ecr_repositories
}

# IRSA for Jenkins
module "jenkins_irsa" {
  source = "./modules/irsa"
  
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  namespace         = "jenkins"
  service_account   = "jenkins"
  
  policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
  ]
}

# IRSA for ArgoCD
module "argocd_irsa" {
  source = "./modules/irsa"
  
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  namespace         = "argocd"
  service_account   = "argocd-application-controller"
  
  policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ]
}