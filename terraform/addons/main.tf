locals {
  name_prefix = "coder-demo"
}

# Installs the AWS Load Balancer Controller (internal NLB provisioning) and the
# Secrets Store CSI Driver + AWS provider (Secrets Manager mounts) — both are
# built into AKS's cloud-provider integration but need to be installed explicitly
# on EKS.
module "addons" {
  source = "./modules/addons"

  cluster_name      = var.cluster_name
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider_url = var.oidc_provider_url
  vpc_id            = var.vpc_id
  region            = var.region
  tags              = var.tags
}

module "secrets" {
  source = "./modules/secrets"

  name_prefix       = local.name_prefix
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider_url = var.oidc_provider_url

  anthropic_api_key       = var.anthropic_api_key
  postgres_admin_password = var.postgres_admin_password

  tags = var.tags
}

module "rds" {
  source = "./modules/rds"

  name                      = "${local.name_prefix}-postgres"
  vpc_id                    = var.vpc_id
  database_subnet_ids       = var.database_subnet_ids
  allowed_security_group_id = var.cluster_security_group_id

  engine_version = var.postgres_engine_version
  instance_class = var.postgres_instance_class
  storage_gb     = var.postgres_storage_gb
  admin_username = var.postgres_admin_username
  admin_password = var.postgres_admin_password

  tags = var.tags
}
