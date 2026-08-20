data "aws_caller_identity" "current" {}

locals {
  # Access entries need the real IAM role ARN, not the STS assumed-role
  # session ARN aws_caller_identity returns for SSO/assumed-role callers.
  # String surgery isn't enough either — SSO roles have a path
  # (/aws-reserved/sso.amazonaws.com/...) the assumed-role ARN omits, so look
  # the role up by name instead.
  caller_arn        = data.aws_caller_identity.current.arn
  caller_is_assumed = can(regex("^arn:aws:sts::[0-9]+:assumed-role/", local.caller_arn))
  caller_role_name  = local.caller_is_assumed ? split("/", local.caller_arn)[1] : null

  deployer_principal_arn = local.caller_is_assumed ? data.aws_iam_role.deployer[0].arn : local.caller_arn
}

data "aws_iam_role" "deployer" {
  count = local.caller_is_assumed ? 1 : 0
  name  = local.caller_role_name
}

# ── Cluster IAM role ───────────────────────────────────────────────────────────

resource "aws_iam_role" "cluster" {
  name = "${var.name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── EKS cluster ─────────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # Modern IAM-native cluster access (replaces the legacy aws-auth ConfigMap).
  access_config {
    authentication_mode = "API"
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# Grants the deploying IAM principal (whoever runs `task infra`) cluster-admin —
# the equivalent of AKS's `az aks get-credentials --admin`.
resource "aws_eks_access_entry" "deployer" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = local.deployer_principal_arn
}

resource "aws_eks_access_policy_association" "deployer_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = local.deployer_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# ── OIDC provider — enables IRSA (IAM Roles for Service Accounts) ──────────────

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  tags = var.tags
}

# ── Node group IAM role ────────────────────────────────────────────────────────

resource "aws_iam_role" "node" {
  name = "${var.name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ── System node group ──────────────────────────────────────────────────────────

resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "system"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.node_subnet_ids
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_count
    min_size     = var.node_min_count
    max_size     = var.node_max_count
  }

  update_config {
    max_unavailable = 1
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}
