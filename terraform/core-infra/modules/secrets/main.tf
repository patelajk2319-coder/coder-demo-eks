# ── Secrets ────────────────────────────────────────────────────────────────────
# Declared individually — one resource per secret, matching the AKS repo's
# Key Vault secrets (each held as its own object rather than one JSON blob).
#
# No Anthropic API key secret here — AI Bridge routes through Amazon Bedrock
# instead (see the coder_bedrock_invoke policy below), authenticated via this
# same IRSA role rather than a static key held in Secrets Manager.

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

data "aws_iam_policy_document" "coder_assume" {
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
      values   = ["system:serviceaccount:coder:coder"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "coder" {
  name               = "${var.name_prefix}-coder-secrets"
  assume_role_policy = data.aws_iam_policy_document.coder_assume.json
  tags               = var.tags
}

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

resource "aws_iam_policy" "coder_secrets_read" {
  name   = "${var.name_prefix}-coder-secrets-read"
  policy = data.aws_iam_policy_document.coder_secrets_read.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "coder_secrets_read" {
  role       = aws_iam_role.coder.name
  policy_arn = aws_iam_policy.coder_secrets_read.arn
}

# ── Bedrock — AI Bridge's model backend ────────────────────────────────────────
# IRSA (this same role), not static keys — AWS's own recommended pattern for
# AI Bridge running on EKS. Scoped to Anthropic models only, not all of Bedrock.
# Cross-region inference profiles (the eu.* model IDs AI Bridge is configured
# with) route to underlying foundation models in other eu-* regions, so the
# foundation-model resource can't be pinned to a single region.

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

resource "aws_iam_policy" "coder_bedrock_invoke" {
  name   = "${var.name_prefix}-coder-bedrock-invoke"
  policy = data.aws_iam_policy_document.coder_bedrock_invoke.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "coder_bedrock_invoke" {
  role       = aws_iam_role.coder.name
  policy_arn = aws_iam_policy.coder_bedrock_invoke.arn
}
