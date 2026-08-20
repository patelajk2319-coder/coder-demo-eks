output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "database_subnet_ids" {
  description = "IDs of the isolated RDS subnets — needed by terraform/addons"
  value       = module.vpc.database_subnet_ids
}

output "cluster_security_group_id" {
  description = "ID of the EKS cluster's shared security group — needed by terraform/addons for RDS ingress"
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider — needed by terraform/addons for IRSA role trust policies"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "URL of the cluster's OIDC issuer — needed by terraform/addons for IRSA role trust policies"
  value       = module.eks.oidc_provider_url
}
