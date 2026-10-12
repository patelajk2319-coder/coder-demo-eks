locals {
  coder_namespace  = "coder"
  helm_values_root = abspath("${path.module}/../../helm-chart/coder-stack/values")
  # Fixed, not a variable — see terraform/core-infra/provider.tf.
  aws_region = "eu-west-1"

  postgres_connection_url = "postgresql://${data.terraform_remote_state.core.outputs.rds_admin_username}:${var.postgres_admin_password}@${data.terraform_remote_state.core.outputs.rds_endpoint}/${data.terraform_remote_state.core.outputs.rds_database_name}?sslmode=require"
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
# Patched post-install so the annotation survives chart upgrades.

resource "kubernetes_annotations" "coder_sa" {
  api_version = "v1"
  kind        = "ServiceAccount"
  metadata {
    name      = "coder"
    namespace = local.coder_namespace
  }
  annotations = {
    "eks.amazonaws.com/role-arn" = data.terraform_remote_state.core.outputs.coder_identity_role_arn
  }

  depends_on = [helm_release.coder]
}

# ── Cluster-scoped RBAC for workspace provisioning ─────────────────────────────

# The chart's default Role is namespace-scoped; templates provision one
# namespace per workspace, so this needs to be cluster-wide.
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
        region = local.aws_region
        objects = join("", [
          "- objectName: \"${data.terraform_remote_state.core.outputs.github_oauth_secret_arn}\"\n",
          "  objectType: \"secretsmanager\"\n",
        ])
      }
      # Sync to a Kubernetes Secret so Helm can reference it via secretEnvs.
      secretObjects = [
        {
          secretName = "coder-secrets"
          type       = "Opaque"
          data = [
            {
              objectName = data.terraform_remote_state.core.outputs.github_oauth_secret_arn
              key        = "CODER_EXTERNAL_AUTH_0_CLIENT_SECRET"
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
        # Dedicated pool, isolated from platform add-ons too — see
        # core-infra's eks_managed_node_groups.
        nodeSelector = {
          "coder.com/node-pool" = "coderd"
        }
        tolerations = [
          {
            key      = "coder.com/node-pool"
            operator = "Equal"
            value    = "coderd"
            effect   = "NoSchedule"
          }
        ]
        # No coder.strategy/maxSurge in v2.36.5's chart — rollout headroom
        # comes from the resource requests in coder.yaml instead.
        serviceAccount = {
          annotations = {
            "eks.amazonaws.com/role-arn" = data.terraform_remote_state.core.outputs.coder_identity_role_arn
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
          { name = "CODER_PG_CONNECTION_URL", value = local.postgres_connection_url },
          { name = "CODER_AUDIT_LOGGING", value = "true" },
          { name = "CODER_EXPERIMENTS", value = "ai-tasks" },
          { name = "CODER_TELEMETRY_ENABLE", value = "true" },
          { name = "CODER_SESSION_DURATION", value = "720h" },
          { name = "CODER_MAX_TOKEN_LIFETIME", value = "876h" },
          # Owner-created tokens (the coderd provider's terraform-coderd token) hit
          # this cap instead of CODER_MAX_TOKEN_LIFETIME — defaults to 168h if unset.
          { name = "CODER_MAX_ADMIN_TOKEN_LIFETIME", value = "876h" },
          { name = "CODER_DEFAULT_OAUTH_REFRESH_LIFETIME", value = "876h" },
          { name = "CODER_AIBRIDGE_ENABLED", value = "true" },
          # Authenticated via this pod's IRSA role, not a static API key.
          { name = "CODER_AIBRIDGE_BEDROCK_REGION", value = "eu-west-1" },
          # Needs CODER_VERSION >= 2.36.5, else Bedrock rejects claude-sonnet-5's
          # "adaptive" thinking schema.
          { name = "CODER_AIBRIDGE_BEDROCK_MODEL", value = "eu.anthropic.claude-sonnet-5" },
          { name = "CODER_AIBRIDGE_BEDROCK_SMALL_FAST_MODEL", value = "eu.anthropic.claude-haiku-4-5-20251001-v1:0" },
          # Device flow, not browser-redirect — the redirect callback is built
          # from CODER_ACCESS_URL, which a developer's browser can't reach.
          { name = "CODER_EXTERNAL_AUTH_0_ID", value = "github" },
          { name = "CODER_EXTERNAL_AUTH_0_TYPE", value = "github" },
          { name = "CODER_EXTERNAL_AUTH_0_CLIENT_ID", value = var.github_oauth_client_id },
          { name = "CODER_EXTERNAL_AUTH_0_DEVICE_FLOW", value = "true" },
          # Single scope, not "repo workflow" — GitHub's device endpoint keeps
          # only the last of multiple scopes, silently dropping "repo".
          { name = "CODER_EXTERNAL_AUTH_0_SCOPES", value = "repo" },
          {
            name = "CODER_EXTERNAL_AUTH_0_CLIENT_SECRET"
            valueFrom = {
              secretKeyRef = {
                name = "coder-secrets"
                key  = "CODER_EXTERNAL_AUTH_0_CLIENT_SECRET"
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
