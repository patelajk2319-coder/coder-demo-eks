terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
  }
}

# Uses the kubeconfig written by 10_deploy_core_infra.sh
# (aws eks update-kubeconfig --alias <cluster>-admin).
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kubeconfig_context
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = var.kubeconfig_context
  }
}
