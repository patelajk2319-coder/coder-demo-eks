locals {
  coder_namespace  = "coder"
  helm_values_root = abspath("${path.module}/../../helm-chart/coder-stack/values")
}

# ── Namespace ──────────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "coder" {
  metadata {
    name = local.coder_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# ── Service account annotated with the IRSA role ───────────────────────────────
# The Coder Helm chart creates its own service account; we patch it post-install
# via a separate resource so the annotation survives chart upgrades.

resource "kubernetes_annotations" "coder_sa" {
  api_version = "v1"
  kind        = "ServiceAccount"
  metadata {
    name      = "coder"
    namespace = local.coder_namespace
  }
  annotations = {
    "eks.amazonaws.com/role-arn" = var.coder_identity_role_arn
  }

  depends_on = [helm_release.coder]
}

# ── Cluster-scoped RBAC for workspace provisioning ─────────────────────────────
# The chart's default Role only covers pods/PVCs/deployments inside the coder
# namespace. Workspace templates provision a namespace per workspace
# (coder-ws-<owner>-<workspace>), so the coder service account needs these
# cluster-wide.

resource "kubernetes_cluster_role" "coder_workspace_provisioner" {
  metadata {
    name = "coder-workspace-provisioner"
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "pods", "persistentvolumeclaims"]
    verbs      = ["create", "delete", "deletecollection", "get", "list", "patch", "update", "watch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["networkpolicies"]
    verbs      = ["create", "delete", "deletecollection", "get", "list", "patch", "update", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "coder_workspace_provisioner" {
  metadata {
    name = "coder-workspace-provisioner"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.coder_workspace_provisioner.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "coder"
    namespace = local.coder_namespace
  }

  depends_on = [helm_release.coder]
}

# ── SecretProviderClass — pulls secrets from Secrets Manager via CSI driver ────

resource "kubernetes_manifest" "secret_provider_class" {
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "coder-secrets"
      namespace = local.coder_namespace
    }
    spec = {
      provider = "aws"
      parameters = {
        region  = var.region
        objects = "- objectName: \"${var.anthropic_secret_arn}\"\n  objectType: \"secretsmanager\"\n"
      }
      # Sync to a Kubernetes Secret so Helm can reference it via secretEnvs.
      secretObjects = [
        {
          secretName = "coder-secrets"
          type       = "Opaque"
          data = [
            {
              objectName = var.anthropic_secret_arn
              key        = "CODER_AIBRIDGE_ANTHROPIC_KEY"
            },
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_namespace.coder]
}

# ── Coder Helm release ─────────────────────────────────────────────────────────

resource "helm_release" "coder" {
  name       = "coder"
  repository = "https://helm.coder.com/v2"
  chart      = "coder"
  version    = var.coder_version
  namespace  = kubernetes_namespace.coder.metadata[0].name

  values = [
    file("${local.helm_values_root}/coder/coder.yaml"),
    yamlencode({
      coder = {
        serviceAccount = {
          annotations = {
            "eks.amazonaws.com/role-arn" = var.coder_identity_role_arn
          }
        }
        volumes = [
          {
            name = "secrets-store"
            csi = {
              driver   = "secrets-store.csi.k8s.io"
              readOnly = true
              volumeAttributes = {
                secretProviderClass = "coder-secrets"
              }
            }
          }
        ]
        volumeMounts = [
          {
            name      = "secrets-store"
            mountPath = "/mnt/secrets"
            readOnly  = true
          }
        ]
        env = [
          { name = "CODER_ACCESS_URL", value = var.coder_access_url },
          { name = "CODER_PG_CONNECTION_URL", value = var.postgres_connection_url },
          { name = "CODER_AUDIT_LOGGING", value = "true" },
          { name = "CODER_EXPERIMENTS", value = "ai-tasks" },
          { name = "CODER_TELEMETRY_ENABLE", value = "true" },
          { name = "CODER_SESSION_DURATION", value = "720h" },
          { name = "CODER_MAX_TOKEN_LIFETIME", value = "876h" },
          { name = "CODER_DEFAULT_OAUTH_REFRESH_LIFETIME", value = "876h" },
          { name = "CODER_AIBRIDGE_ENABLED", value = "true" },
          {
            name = "CODER_AIBRIDGE_ANTHROPIC_KEY"
            valueFrom = {
              secretKeyRef = {
                name = "coder-secrets"
                key  = "CODER_AIBRIDGE_ANTHROPIC_KEY"
              }
            }
          },
        ]
      }
    }),
  ]

  wait            = true
  timeout         = 300
  cleanup_on_fail = true

  depends_on = [kubernetes_manifest.secret_provider_class]
}
