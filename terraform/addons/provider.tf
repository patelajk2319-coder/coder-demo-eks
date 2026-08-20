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
  region = local.aws_region
}

# Uses the kubeconfig written by 10_deploy_core_infra.sh
# (aws eks update-kubeconfig --alias <cluster>-admin) once the cluster exists —
# unlike a live cluster data source, this doesn't break on a fresh deploy.
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

# Reads terraform/core-infra's outputs directly — the Terraform-native way to
# bridge two deliberately separate states (see terraform/core-infra/provider.tf
# for why core-infra can't share a state with anything needing kubernetes/helm).
data "terraform_remote_state" "core" {
  backend = "local"
  config = {
    path = "${path.module}/../core-infra/terraform.tfstate"
  }
}
