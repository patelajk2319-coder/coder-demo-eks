terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
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

provider "aws" {
  region = var.region
}

# Uses the kubeconfig written by 10_deploy_core_infra.sh
# (aws eks update-kubeconfig --alias <cluster>-admin) once the cluster exists —
# unlike a live cluster data source, this doesn't break on a fresh deploy.
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
