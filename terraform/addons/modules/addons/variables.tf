variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "argocd_github_token" {
  description = "GitHub token Argo CD uses to read this repo's own gitops/ directory"
  type        = string
  sensitive   = true
}

variable "internal_zone_id" {
  description = "Private Route53 zone ID external-dns is scoped to"
  type        = string
}
