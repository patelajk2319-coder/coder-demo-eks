# ── AWS Load Balancer Controller ────────────────────────────────────────────────
# Provisions and manages the internal NLB for Coder's service — the equivalent of
# AKS's built-in cloud-provider annotation-based internal LoadBalancer support.
# Not built into EKS, so it needs its own IAM role (IRSA) and Helm install.

data "aws_iam_policy_document" "alb_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.cluster_name}-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json
  tags               = var.tags
}

# Copied verbatim from upstream (kubernetes-sigs/aws-load-balancer-controller
# docs/install/iam_policy.json) rather than hand-transcribed, to avoid
# missing a statement.
resource "aws_iam_policy" "alb_controller" {
  name   = "${var.cluster_name}-alb-controller"
  policy = file("${path.module}/alb_controller_policy.json")

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller.arn
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

  wait    = true
  timeout = 300

  depends_on = [aws_iam_role_policy_attachment.alb_controller]
}

# ── Secrets Store CSI Driver + AWS provider ────────────────────────────────────
# Mounts Secrets Manager secrets into pods — the equivalent of AKS's built-in
# Key Vault CSI driver. The IRSA role for reading specific secrets lives on the
# *consuming* pod's service account (Coder's), not on this driver itself.

resource "helm_release" "secrets_store_csi_driver" {
  name       = "secrets-store-csi-driver"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = "kube-system"

  set {
    name  = "syncSecret.enabled"
    value = "true"
  }

  # Required for the AWS provider: the CSIDriver object needs projected
  # service-account tokens for these audiences so pods' IRSA identity can be
  # exchanged for AWS credentials. The provider-aws chart's bundled copy of
  # this driver sets this by default; our standalone install needs it explicit.
  set {
    name  = "tokenRequests[0].audience"
    value = "sts.amazonaws.com"
  }

  set {
    name  = "tokenRequests[1].audience"
    value = "pods.eks.amazonaws.com"
  }

  wait    = true
  timeout = 300
}

resource "helm_release" "secrets_store_csi_driver_provider_aws" {
  name       = "secrets-store-csi-driver-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  namespace  = "kube-system"

  # This chart bundles its own copy of secrets-store-csi-driver as a subchart
  # (defaulting to fullnameOverride: secrets-store-csi-driver), which collides
  # with the standalone driver release above. Disable the bundled copy since
  # we already install the driver ourselves.
  set {
    name  = "secrets-store-csi-driver.install"
    value = "false"
  }

  wait    = true
  timeout = 300

  depends_on = [helm_release.secrets_store_csi_driver]
}
