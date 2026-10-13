variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    project     = "coder-demo"
    managed-by  = "terraform"
    environment = "demo"
  }
}

variable "argocd_github_token" {
  description = "GitHub token Argo CD uses to read this repo's own gitops/ directory"
  type        = string
  sensitive   = true
}
