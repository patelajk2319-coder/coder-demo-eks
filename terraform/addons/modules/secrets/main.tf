# ── Secrets ────────────────────────────────────────────────────────────────────
# Declared individually — one resource per secret, matching the AKS repo's
# Key Vault secrets (each held as its own object rather than one JSON blob).

resource "aws_secretsmanager_secret" "anthropic_api_key" {
  name = "${var.name_prefix}-anthropic-api-key"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "anthropic_api_key" {
  secret_id     = aws_secretsmanager_secret.anthropic_api_key.id
  secret_string = var.anthropic_api_key
}

resource "aws_secretsmanager_secret" "postgres_admin_password" {
  name = "${var.name_prefix}-postgres-admin-password"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "postgres_admin_password" {
  secret_id     = aws_secretsmanager_secret.postgres_admin_password.id
  secret_string = var.postgres_admin_password
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

# Least privilege — read-only, scoped to just the two secrets Coder needs.
data "aws_iam_policy_document" "coder_secrets_read" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [
      aws_secretsmanager_secret.anthropic_api_key.arn,
      aws_secretsmanager_secret.postgres_admin_password.arn,
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
