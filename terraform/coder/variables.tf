variable "kubeconfig_context" {
  description = "kubectl context name written by 10_deploy_core_infra.sh (e.g. coder-demo-eks-admin)"
  type        = string
}

variable "region" {
  description = "AWS region — required by the Secrets Store CSI Driver's AWS provider to locate secrets"
  type        = string
}

variable "coder_access_url" {
  description = "URL at which Coder is reachable (internal NLB hostname; used by workspace agents)"
  type        = string
}

variable "coder_version" {
  description = "Coder Helm chart version to deploy"
  type        = string
  default     = "2.33.6"
}

variable "postgres_connection_url" {
  description = "PostgreSQL connection URL for Coder (postgresql://user:pass@host/db?sslmode=require)"
  type        = string
  sensitive   = true
}

variable "anthropic_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the Anthropic API key"
  type        = string
}

variable "coder_identity_role_arn" {
  description = "IAM role ARN (IRSA) used by the Coder service account to read Secrets Manager"
  type        = string
}
