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
    "eks.amazonaws.com/role-arn" = data.terraform_remote_state.core.outputs.coder_identity_role_arn
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
          # Amazon Bedrock as AI Bridge's model backend, not a direct Anthropic
          # API key — authenticated via this pod's own IRSA role (see
          # coder_bedrock_invoke in terraform/core-infra/modules/secrets), so
          # there's no static key to store or rotate.
          { name = "CODER_AIBRIDGE_BEDROCK_REGION", value = "eu-west-1" },
          # claude-sonnet-5 needs CODER_VERSION >= 2.36.5 — v2.33.6's AI Bridge
          # doesn't know this model requires the "adaptive" thinking schema
          # (bedrockModelRequiresAdaptiveThinking() didn't list claude-sonnet-5
          # until 2.36.5), so it let Claude Code's default "enabled"-shape
          # thinking request through unconverted, and Bedrock rejected it.
          # claude-sonnet-4-5/claude-haiku-4-5 both work around that gap but
          # are subject to Anthropic's account-level Bedrock "use case
          # details" attestation, which has intermittently gated one or the
          # other during testing — sonnet-5 doesn't hit that gate.
          { name = "CODER_AIBRIDGE_BEDROCK_MODEL", value = "eu.anthropic.claude-sonnet-5" },
          { name = "CODER_AIBRIDGE_BEDROCK_SMALL_FAST_MODEL", value = "eu.anthropic.claude-haiku-4-5-20251001-v1:0" },
          # External auth — lets workspace templates use data.coder_external_auth
          # instead of a shared PAT template variable. Each developer authorizes
          # their own GitHub identity once via the dashboard.
          #
          # Uses GitHub's device flow, not the browser-redirect flow: the normal
          # flow's OAuth callback is built from CODER_ACCESS_URL, which is the
          # internal NLB hostname — never reachable by a developer's browser (see
          # README) — so GitHub would reject it as an unregistered redirect_uri.
          # Device flow has no callback at all (the user enters a code at
          # github.com/login/device instead), sidestepping the problem entirely.
          { name = "CODER_EXTERNAL_AUTH_0_ID", value = "github" },
          { name = "CODER_EXTERNAL_AUTH_0_TYPE", value = "github" },
          { name = "CODER_EXTERNAL_AUTH_0_CLIENT_ID", value = var.github_oauth_client_id },
          { name = "CODER_EXTERNAL_AUTH_0_DEVICE_FLOW", value = "true" },
          # Coder's default scopes for GitHub are "repo workflow", but its device
          # code request encodes multiple scopes as repeated query params instead
          # of one space-joined value — GitHub's device endpoint keeps only the
          # last one, silently dropping "repo" (the one git clone/pull actually
          # needs). Overriding to a single scope sidesteps the encoding bug.
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
