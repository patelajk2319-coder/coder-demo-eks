terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # matches terraform/core-infra — the IAM submodule needs >= 6.28
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
  region = local.aws_region
}

# Uses the kubeconfig written by 10_deploy_core_infra.sh, not a live cluster
# data source — so this doesn't break on a fresh deploy.
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "${data.terraform_remote_state.core.outputs.cluster_name}-admin"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "${data.terraform_remote_state.core.outputs.cluster_name}-admin"
  }
}

# Bridges the two deliberately separate states — see
# terraform/core-infra/provider.tf for why.
data "terraform_remote_state" "core" {
  backend = "local"
  config = {
    path = "${path.module}/../core-infra/terraform.tfstate"
  }
}
