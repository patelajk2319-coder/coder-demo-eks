# ── AWS Load Balancer Controller ────────────────────────────────────────────────
# Manages Coder's internal NLB — not built into EKS, needs its own IRSA role.

module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "${var.cluster_name}-alb-controller"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  attach_load_balancer_controller_policy = true

  tags = var.tags
}

resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"

    annotations = {
      "eks.amazonaws.com/role-arn" = module.alb_controller_irsa.arn
    }

    labels = {
      "app.kubernetes.io/name"       = "aws-load-balancer-controller"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Helm release moved to gitops/addons/ (Argo CD-managed) — see
# gitops/addons/alb-controller-app.yaml. The pre-created SA above stays here.

# ── Secrets Store CSI Driver + AWS provider ────────────────────────────────────
# Mounts Secrets Manager secrets into pods; the IRSA role lives on the consumer
# (Coder's). Both Helm releases moved to gitops/addons/ (Argo CD-managed) — see
# gitops/addons/secrets-store-csi-driver-app.yaml and
# gitops/addons/secrets-store-csi-driver-provider-aws-app.yaml.

# ── EBS CSI Driver ──────────────────────────────────────────────────────────────
# Installed as an EKS addon (not Helm) — AWS ships and versions it directly.

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "${var.cluster_name}-ebs-csi"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  attach_ebs_csi_policy = true

  tags = var.tags
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_irsa.arn
  tags                     = var.tags

  # Only the controller Deployment is pinned — the node plugin (a DaemonSet)
  # must keep running everywhere, workspaces pool included.
  configuration_values = jsonencode({
    controller = {
      nodeSelector = { "coder.com/node-pool" = "system" }
      tolerations = [
        { key = "CriticalAddonsOnly", operator = "Exists" },
        { operator = "Exists", effect = "NoExecute", tolerationSeconds = 300 },
        { key = "coder.com/node-pool", operator = "Equal", value = "system", effect = "NoSchedule" },
      ]
    }
  })
}

# gp3 StorageClass moved to gitops/addons/ (Argo CD-managed) — see
# gitops/addons/gp3-storageclass-app.yaml.
