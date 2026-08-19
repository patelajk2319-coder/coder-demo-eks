output "coder_namespace" {
  description = "Kubernetes namespace where Coder is deployed"
  value       = kubernetes_namespace.coder.metadata[0].name
}

output "coder_access_url" {
  description = "URL at which Coder is accessible"
  value       = var.coder_access_url
}
