data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# ── VPC ──────────────────────────────────────────────────────────────────────
# Registry module, not hand-rolled — see CLAUDE.md's module-sourcing policy.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${local.name_prefix}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  # Isolated — no internet route (RDS only).
  database_subnets             = var.database_subnet_cidrs
  create_database_subnet_group = true

  # No workloads scheduled in public subnets — NAT/IGW egress only.
  map_public_ip_on_launch = true

  # Single NAT gateway — demo-appropriate; not multi-AZ HA.
  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                = "1"
    "kubernetes.io/cluster/${local.name_prefix}-eks" = "shared"
  }

  tags = local.common_tags
}

# ── EKS ──────────────────────────────────────────────────────────────────────
# Registry module, not hand-rolled — see CLAUDE.md's module-sourcing policy.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "${local.name_prefix}-eks"
  kubernetes_version = var.kubernetes_version

  vpc_id = module.vpc.vpc_id

  # Node groups — private subnets only.
  subnet_ids = module.vpc.private_subnets

  # Control plane ENIs — public + private, needed for public endpoint routing.
  control_plane_subnet_ids = concat(module.vpc.public_subnets, module.vpc.private_subnets)

  endpoint_public_access  = true
  endpoint_private_access = true

  # Modern IAM-native cluster access (replaces the legacy aws-auth ConfigMap).
  authentication_mode = "API"

  # Grants the deployer cluster-admin — resolves the real IAM role ARN for
  # SSO/assumed-role callers internally (aws_iam_session_context).
  enable_cluster_creator_admin_permissions = true

  enabled_log_types = ["api", "audit", "authenticator"]

  # Pre-creates the control-plane log group with managed retention — avoids
  # EKS auto-creating its own copy (no retention set) on first log write.
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  enable_irsa = true

  # The module sets bootstrap_self_managed_addons = false, unlike a plain
  # aws_eks_cluster — vpc-cni/kube-proxy need before_compute to bootstrap nodes.
  addons = {
    vpc-cni = {
      before_compute = true
    }
    kube-proxy = {
      before_compute = true
    }
    coredns = {
      configuration_values = jsonencode({
        nodeSelector = { "coder.com/node-pool" = "system" }
        tolerations = [
          { key = "CriticalAddonsOnly", operator = "Exists" },
          { key = "node-role.kubernetes.io/control-plane", effect = "NoSchedule" },
          { key = "coder.com/node-pool", operator = "Equal", value = "system", effect = "NoSchedule" },
        ]
      })
    }
  }

  # Dedicated node pools, labeled + tainted — see README's Node Pools section.
  # workspaces is a deferred third pool, not created yet.
  eks_managed_node_groups = {
    coderd = {
      instance_types = [var.node_instance_type]

      min_size     = var.node_min_count
      max_size     = var.node_max_count
      desired_size = var.node_desired_count
      # desired_size changes are ignored by default (lifecycle.ignore_changes
      # on scaling_config[0].desired_size) — safe for an autoscaler to manage.

      labels = {
        "coder.com/node-pool" = "coderd"
      }
      taints = {
        dedicated = {
          key    = "coder.com/node-pool"
          value  = "coderd"
          effect = "NO_SCHEDULE"
        }
      }
    }

    system = {
      instance_types = [var.system_node_instance_type]

      min_size     = 1
      max_size     = 3
      desired_size = 2

      labels = {
        "coder.com/node-pool" = "system"
      }
      taints = {
        dedicated = {
          key    = "coder.com/node-pool"
          value  = "system"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  tags = local.common_tags
}

# ── Secrets + Coder workload identity ───────────────────────────────────────

module "secrets" {
  source = "./modules/secrets"

  name_prefix       = local.name_prefix
  oidc_provider_arn = module.eks.oidc_provider_arn

  rds_resource_id    = module.rds.resource_id
  rds_admin_username = local.postgres_admin_username

  github_oauth_client_secret = var.github_oauth_client_secret

  tags = local.common_tags
}

# ── RDS PostgreSQL ───────────────────────────────────────────────────────────

module "rds" {
  source = "./modules/rds"

  name                = "${local.name_prefix}-postgres"
  vpc_id              = module.vpc.vpc_id
  database_subnet_ids = module.vpc.database_subnets
  # Node ENIs carry the module's own dedicated node SG, not the cluster's.
  allowed_security_group_id = module.eks.node_security_group_id

  engine_version = var.postgres_engine_version
  instance_class = var.postgres_instance_class
  storage_gb     = var.postgres_storage_gb
  admin_username = local.postgres_admin_username
  admin_password = var.postgres_admin_password

  tags = local.common_tags
}
