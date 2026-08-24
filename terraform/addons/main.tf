locals {
  # Fixed, not a variable — see terraform/core-infra/provider.tf.
  aws_region = "eu-west-1"
}

# Installs the AWS Load Balancer Controller (internal NLB provisioning) and the
# Secrets Store CSI Driver + AWS provider (Secrets Manager mounts) — both are
# built into AKS's cloud-provider integration but need to be installed explicitly
# on EKS. 

module "addons" {
  source = "./modules/addons"

  cluster_name      = data.terraform_remote_state.core.outputs.cluster_name
  oidc_provider_arn = data.terraform_remote_state.core.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.core.outputs.oidc_provider_url
  vpc_id            = data.terraform_remote_state.core.outputs.vpc_id
  region            = local.aws_region
  tags              = var.tags
}
