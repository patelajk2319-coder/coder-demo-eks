variable "coder_access_url" {
  description = "URL at which Coder is reachable (internal NLB hostname; used by workspace agents)"
  type        = string
}

variable "coder_version" {
  description = "Coder Helm chart version to deploy"
  type        = string
  default     = "2.33.6"
}

variable "postgres_admin_password" {
  description = "RDS PostgreSQL administrator password"
  type        = string
  sensitive   = true
}

variable "github_oauth_client_id" {
  description = "GitHub OAuth App client ID, for Coder's external auth integration"
  type        = string
}
