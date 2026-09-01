variable "name_prefix" {
  description = "Name prefix used for secret names"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the cluster's OIDC issuer, without the https:// prefix"
  type        = string
}

variable "anthropic_api_key" {
  description = "Anthropic API key to store in Secrets Manager"
  type        = string
  sensitive   = true
}

variable "postgres_admin_password" {
  description = "PostgreSQL admin password to store in Secrets Manager"
  type        = string
  sensitive   = true
}

variable "github_oauth_client_secret" {
  description = "GitHub OAuth App client secret, for Coder's external auth integration"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
