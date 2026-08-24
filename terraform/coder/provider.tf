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
  config_context = "${data.terraform_remote_state.core.outputs.cluster_name}-admin"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "${data.terraform_remote_state.core.outputs.cluster_name}-admin"
  }
}

# Reads terraform/core-infra's outputs directly — the Terraform-native way to
# bridge deliberately separate states. Nothing here is read from
# terraform/addons (the ALB controller/CSI driver just need to be installed,
# not read from — no data dependency, only an ordering one).
data "terraform_remote_state" "core" {
  backend = "local"
  config = {
    path = "${path.module}/../core-infra/terraform.tfstate"
  }
}
