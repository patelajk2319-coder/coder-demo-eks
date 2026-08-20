locals {
  name_prefix = "coder-demo"
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

module "secrets" {
  source = "./modules/secrets"

  name_prefix       = local.name_prefix
  oidc_provider_arn = data.terraform_remote_state.core.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.core.outputs.oidc_provider_url

  anthropic_api_key       = var.anthropic_api_key
  postgres_admin_password = var.postgres_admin_password

  tags = var.tags
}

module "rds" {
  source = "./modules/rds"

  name                      = "${local.name_prefix}-postgres"
  vpc_id                    = data.terraform_remote_state.core.outputs.vpc_id
  database_subnet_ids       = data.terraform_remote_state.core.outputs.database_subnet_ids
  allowed_security_group_id = data.terraform_remote_state.core.outputs.cluster_security_group_id

  engine_version = var.postgres_engine_version
  instance_class = var.postgres_instance_class
  storage_gb     = var.postgres_storage_gb
  admin_username = var.postgres_admin_username
  admin_password = var.postgres_admin_password

  tags = var.tags
}
