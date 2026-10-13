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

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.alb_controller.metadata[0].name
  }

  # Pin to the system node pool, isolated from coderd — see
  # core-infra's eks_managed_node_groups.
  values = [
    yamlencode({
      nodeSelector = { "coder.com/node-pool" = "system" }
      tolerations = [
        {
          key      = "coder.com/node-pool"
          operator = "Equal"
          value    = "system"
          effect   = "NoSchedule"
        }
      ]
    }),
  ]

  wait    = true
  timeout = 300
}

# ── Secrets Store CSI Driver + AWS provider ────────────────────────────────────
# Mounts Secrets Manager secrets into pods; the IRSA role lives on the consumer (Coder's).

resource "helm_release" "secrets_store_csi_driver" {
  name       = "secrets-store-csi-driver"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = "kube-system"

  set {
    name  = "syncSecret.enabled"
    value = "true"
  }

  # Needed so pods' IRSA identity can be exchanged for AWS credentials —
  # the bundled copy of this driver sets it by default, our standalone one doesn't.
  set {
    name  = "tokenRequests[0].audience"
    value = "sts.amazonaws.com"
  }

  set {
    name  = "tokenRequests[1].audience"
    value = "pods.eks.amazonaws.com"
  }

  # Only Coder's own pod mounts a secret via this driver — pin it there.
  # No explicit toleration: this chart's default already matches any taint.
  set {
    name  = "linux.nodeSelector.coder\\.com/node-pool"
    value = "coderd"
  }

  wait    = true
  timeout = 300
}

resource "helm_release" "secrets_store_csi_driver_provider_aws" {
  name       = "secrets-store-csi-driver-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  namespace  = "kube-system"

  # This chart bundles its own copy of the driver, which collides with the
  # standalone release above — disable it.
  set {
    name  = "secrets-store-csi-driver.install"
    value = "false"
  }

  # Same pool as the driver above; this chart has no default toleration, so
  # one has to be set explicitly.
  values = [
    yamlencode({
      nodeSelector = { "coder.com/node-pool" = "coderd" }
      tolerations = [
        {
          key      = "coder.com/node-pool"
          operator = "Equal"
          value    = "coderd"
          effect   = "NoSchedule"
        }
      ]
    }),
  ]

  wait    = true
  timeout = 300

  depends_on = [helm_release.secrets_store_csi_driver]
}

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
