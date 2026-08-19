module "logs" {
  source = "./modules/logs"

  cluster_name   = "${local.name_prefix}-eks"
  retention_days = var.log_retention_days
  tags           = local.common_tags
}

module "vpc" {
  source = "./modules/vpc"

  name                  = "${local.name_prefix}-vpc"
  cidr                  = var.vpc_cidr
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  cluster_name          = "${local.name_prefix}-eks"
  tags                  = local.common_tags
}

module "eks" {
  source = "./modules/eks"

  name               = "${local.name_prefix}-eks"
  kubernetes_version = var.kubernetes_version
  subnet_ids         = concat(module.vpc.public_subnet_ids, module.vpc.private_subnet_ids)
  node_subnet_ids    = module.vpc.private_subnet_ids

  node_instance_type = var.node_instance_type
  node_desired_count = var.node_desired_count
  node_min_count     = var.node_min_count
  node_max_count     = var.node_max_count

  tags = local.common_tags

  depends_on = [module.logs]
}

# Installs the AWS Load Balancer Controller (internal NLB provisioning) and the
# Secrets Store CSI Driver + AWS provider (Secrets Manager mounts) — both are
# built into AKS's cloud-provider integration but need to be installed explicitly
# on EKS.
module "addons" {
  source = "./modules/addons"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  vpc_id            = module.vpc.vpc_id
  region            = var.region
  tags              = local.common_tags

  depends_on = [module.eks]
}

module "secrets" {
  source = "./modules/secrets"

  name_prefix       = local.name_prefix
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  anthropic_api_key       = var.anthropic_api_key
  postgres_admin_password = var.postgres_admin_password

  tags = local.common_tags

  depends_on = [module.eks]
}

module "rds" {
  source = "./modules/rds"

  name                      = "${local.name_prefix}-postgres"
  vpc_id                    = module.vpc.vpc_id
  database_subnet_ids       = module.vpc.database_subnet_ids
  allowed_security_group_id = module.eks.cluster_security_group_id

  engine_version = var.postgres_engine_version
  instance_class = var.postgres_instance_class
  storage_gb     = var.postgres_storage_gb
  admin_username = var.postgres_admin_username
  admin_password = var.postgres_admin_password

  tags = local.common_tags

  depends_on = [module.vpc, module.eks]
}
