# ── Secrets ────────────────────────────────────────────────────────────────────
# No Anthropic API key here — AI Bridge routes through Bedrock instead (below).

data "aws_caller_identity" "current" {}

resource "aws_secretsmanager_secret" "postgres_admin_password" {
  name = "${var.name_prefix}-postgres-admin-password"
  tags = var.tags

  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "postgres_admin_password" {
  secret_id     = aws_secretsmanager_secret.postgres_admin_password.id
  secret_string = var.postgres_admin_password
}

resource "aws_secretsmanager_secret" "github_oauth_client_secret" {
  name = "${var.name_prefix}-github-oauth-client-secret"
  tags = var.tags

  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "github_oauth_client_secret" {
  secret_id     = aws_secretsmanager_secret.github_oauth_client_secret.id
  secret_string = var.github_oauth_client_secret
}

# ── Coder workload identity — IRSA role for the Coder pod's service account ───

# Least privilege — read-only, scoped to just the secrets Coder needs.
data "aws_iam_policy_document" "coder_secrets_read" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [
      aws_secretsmanager_secret.postgres_admin_password.arn,
      aws_secretsmanager_secret.github_oauth_client_secret.arn,
    ]
  }
}

# ── Bedrock — AI Bridge's model backend ────────────────────────────────────────
# eu-* wildcard, not eu-west-1 — inference profiles route cross-region.

data "aws_iam_policy_document" "coder_bedrock_invoke" {
  statement {
    effect  = "Allow"
    actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = [
      "arn:aws:bedrock:eu-west-1:${data.aws_caller_identity.current.account_id}:inference-profile/*.anthropic.*",
      "arn:aws:bedrock:eu-*::foundation-model/anthropic.*",
    ]
  }
}

# ── Coder IRSA role ─────────────────────────────────────────────────────────

module "coder_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "${var.name_prefix}-coder-secrets"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["coder:coder"]
    }
  }

  source_policy_documents = [
    data.aws_iam_policy_document.coder_secrets_read.json,
    data.aws_iam_policy_document.coder_bedrock_invoke.json,
  ]

  tags = var.tags
}
