locals {
  # Fixed, not a variable — see terraform/core-infra/provider.tf.
  aws_region = "eu-west-1"
}

# ALB controller + Secrets Store CSI driver — built into AKS, not EKS.
module "addons" {
  source = "./modules/addons"

  cluster_name        = data.terraform_remote_state.core.outputs.cluster_name
  oidc_provider_arn   = data.terraform_remote_state.core.outputs.oidc_provider_arn
  vpc_id              = data.terraform_remote_state.core.outputs.vpc_id
  internal_zone_id    = data.terraform_remote_state.core.outputs.internal_zone_id
  region              = local.aws_region
  tags                = var.tags
  argocd_github_token = var.argocd_github_token
}
