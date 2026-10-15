locals {
  coder_namespace = "coder"
  # Fixed, not a variable — see terraform/core-infra/provider.tf.
  aws_region = "eu-west-1"
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
# Pre-created, not chart-created — the Helm release (gitops/coder/) is told
# serviceAccount.create=false and references this by name instead.

resource "kubernetes_service_account" "coder" {
  metadata {
    name      = "coder"
    namespace = local.coder_namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = data.terraform_remote_state.core.outputs.coder_identity_role_arn
    }

    labels = {
      "app.kubernetes.io/name"       = "coder"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# ── Dynamic config the git-tracked Helm values can't know ──────────────────────
# RBAC and the Helm release itself live in gitops/coder/ (Argo CD-managed) —
# this is just the handful of values only Terraform can compute.

resource "kubernetes_config_map" "coder_config" {
  metadata {
    name      = "coder-config"
    namespace = local.coder_namespace
  }

  data = {
    # No password — Coder connects via IAM auth (CODER_PG_AUTH=awsiamrds).
    # Port is required here — the awsiamrds driver needs host:port to build
    # the RDS auth token, unlike a normal password-based connection string.
    pg-connection-url = "postgresql://${data.terraform_remote_state.core.outputs.rds_admin_username}@${data.terraform_remote_state.core.outputs.rds_endpoint}:5432/${data.terraform_remote_state.core.outputs.rds_database_name}?sslmode=require"

    github-oauth-client-id = var.github_oauth_client_id
  }

  depends_on = [kubernetes_namespace.coder]
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
