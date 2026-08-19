output "anthropic_secret_arn" {
  description = "ARN of the Anthropic API key secret"
  value       = aws_secretsmanager_secret.anthropic_api_key.arn
}

output "anthropic_secret_name" {
  description = "Name of the Anthropic API key secret"
  value       = aws_secretsmanager_secret.anthropic_api_key.name
}

output "postgres_secret_arn" {
  description = "ARN of the PostgreSQL admin password secret"
  value       = aws_secretsmanager_secret.postgres_admin_password.arn
}

output "coder_role_arn" {
  description = "IAM role ARN (IRSA) for the Coder service account — read access to Secrets Manager"
  value       = aws_iam_role.coder.arn
}
