variable "region" {
  description = "AWS region"
  type        = string
}

variable "kubeconfig_context" {
  description = "kubectl context name written by 10_deploy_core_infra.sh (e.g. coder-demo-eks-admin)"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster (from terraform/core-infra)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID (from terraform/core-infra)"
  type        = string
}

variable "database_subnet_ids" {
  description = "Isolated RDS subnet IDs (from terraform/core-infra)"
  type        = list(string)
}

variable "cluster_security_group_id" {
  description = "EKS cluster's shared security group ID (from terraform/core-infra)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider (from terraform/core-infra)"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the cluster's OIDC issuer (from terraform/core-infra)"
  type        = string
}

variable "postgres_admin_username" {
  description = "RDS PostgreSQL administrator username"
  type        = string
  default     = "pgadmin"
}

variable "postgres_admin_password" {
  description = "RDS PostgreSQL administrator password"
  type        = string
  sensitive   = true
}

variable "postgres_engine_version" {
  description = "PostgreSQL major engine version"
  type        = string
  default     = "16"
}

variable "postgres_instance_class" {
  description = "Instance class for the RDS PostgreSQL instance"
  type        = string
  default     = "db.t3.medium"
}

variable "postgres_storage_gb" {
  description = "Allocated storage in GB for the RDS instance"
  type        = number
  default     = 32
}

variable "anthropic_api_key" {
  description = "Anthropic API key — stored in Secrets Manager, never passed to Coder Terraform"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    project     = "coder-demo"
    managed-by  = "terraform"
    environment = "demo"
  }
}
