output "github_oauth_secret_arn" {
  description = "ARN of the GitHub OAuth client secret"
  value       = aws_secretsmanager_secret.github_oauth_client_secret.arn
}

output "coder_role_arn" {
  description = "IAM role ARN (IRSA) for the Coder service account — read access to Secrets Manager"
  value       = aws_iam_role.coder.arn
}
