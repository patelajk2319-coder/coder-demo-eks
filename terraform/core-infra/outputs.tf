output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "rds_endpoint" {
  description = "Connection endpoint (hostname) of the RDS PostgreSQL instance"
  value       = module.rds.address
}

output "rds_database_name" {
  description = "Name of the Coder application database"
  value       = module.rds.database_name
}

output "anthropic_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the Anthropic API key"
  value       = module.secrets.anthropic_secret_arn
}

output "postgres_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the PostgreSQL admin password"
  value       = module.secrets.postgres_secret_arn
}

output "coder_identity_role_arn" {
  description = "IAM role ARN (IRSA) for the Coder service account — read access to Secrets Manager"
  value       = module.secrets.coder_role_arn
}
