variable "name_prefix" {
  description = "Name prefix used for secret names"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider"
  type        = string
}

variable "rds_resource_id" {
  description = "RDS resource ID — scopes the rds-db:connect IAM permission to this instance"
  type        = string
}

variable "rds_admin_username" {
  description = "PostgreSQL username Coder connects as via IAM auth"
  type        = string
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
