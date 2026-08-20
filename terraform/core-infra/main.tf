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
}
